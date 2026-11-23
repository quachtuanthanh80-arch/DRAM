// File: sim/ramulator2_qshield/src/ramulator/controller/plugin/impl/hydra_act.cpp
// Chức năng: Biến thể Hydra cho DRAM thương mại (không dùng VRR), giữ nguyên GCT/RCC/RCT/RCTCT và làm tươi nạn nhân bán kính R bằng ACT + PREpb chuẩn JEDEC.
// Adapted from CMU-SAFARI/ramulator2 (commit 72427a1, MIT License) src/ramulator/controller/plugin/impl/hydra.cpp.

#include <bitset>
#include <climits>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <random>
#include <stdexcept>
#include <unordered_map>
#include <vector>

#include "ramulator/base/base.h"
#include "ramulator/base/param.h"
#include "ramulator/controller/controller_base.h"
#include "ramulator/controller/plugin/i_controller_plugin.h"
#include "ramulator/dram/dram_spec.h"

namespace Ramulator {

class HydraAct : public IControllerPlugin, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IControllerPlugin, HydraAct, "HydraAct")

 private:
  static constexpr int kMitigationSourceId = -99;

  ControllerBase* m_ctrl = nullptr;

  int m_clk = 0;

  int m_tracking_threshold = -1;
  int m_group_threshold = -1;
  int m_row_group_size = -1;
  int m_reset_period_ns = -1;
  int m_rcc_num_per_rank = -1;
  std::string m_rcc_policy;
  int m_blast_radius = 2;
  bool m_is_debug = false;

  int m_reset_period_clk = -1;

  int m_act_cmd_id = -1;
  int m_prepb_cmd_id = -1;
  int m_rd_cmd_id = -1;
  int m_wr_cmd_id = -1;
  int m_rank_level = -1;
  int m_bank_level = -1;
  int m_row_level = -1;
  int m_col_level = -1;
  int m_num_ranks = -1;
  int m_num_banks_per_rank = -1;
  int m_num_rows_per_bank = -1;
  int m_num_cls = -1;

  int m_row_address_bits = -1;
  int m_bank_address_bits = -1;
  int m_counter_bits = -1;
  int m_gct_entries_per_bank = -1;
  int m_gct_index_bits = -1;
  int m_rcc_set_num = -1;
  int m_rcc_index_bits = -1;
  int m_rcc_tag_row_bits = -1;
  int m_rcc_tag_bits = -1;

  int m_total_rct_cl_size = -1;
  int m_total_rct_row_size = -1;
  int m_rct_per_row = -1;
  int m_rct_per_cl = -1;
  int m_group_rct_cl_size = -1;

  struct GCTEntry {
    int group_count = 0;
    bool initialized = false;
  };
  std::vector<std::unordered_map<int, GCTEntry>> m_gct;
  std::vector<std::unordered_map<int, int>> m_rct;
  std::vector<std::unordered_map<int, int>> m_rctct;

  struct RCCEntry {
    int row_id = -1;
    int flat_bank_id = -1;
    int count = 0;
    bool dirty = false;
    AddrVec_t addr_template;
  };
  std::vector<std::vector<std::unordered_map<int, RCCEntry>>> m_rcc;

  std::mt19937 m_generator;
  std::uniform_int_distribution<int> m_rcc_evict_dist;

  size_t s_num_triggers = 0;
  size_t s_num_triggers_rct = 0;
  size_t s_num_victim_refreshes = 0;
  size_t s_num_dropped = 0;
  size_t s_num_read_req = 0;
  size_t s_num_write_req = 0;
  size_t s_num_initialization = 0;
  size_t s_num_eviction = 0;
  size_t s_num_rcc_miss = 0;
  size_t s_gct_check = 0;
  size_t s_rcc_check = 0;
  size_t s_rct_check = 0;
  size_t s_rctct_check = 0;

 public:
  void init() override {
    RAMULATOR_PARSE_PARAM(m_tracking_threshold, int, "hydra_tracking_threshold").required();
    RAMULATOR_PARSE_PARAM(m_group_threshold, int, "hydra_group_threshold").required();
    RAMULATOR_PARSE_PARAM(m_row_group_size, int, "hydra_row_group_size").default_val(128);
    RAMULATOR_PARSE_PARAM(m_reset_period_ns, int, "hydra_reset_period_ns").default_val(64000000);
    RAMULATOR_PARSE_PARAM(m_rcc_num_per_rank, int, "hydra_rcc_num_per_rank").default_val(4096);
    RAMULATOR_PARSE_PARAM(m_rcc_policy, std::string, "hydra_rcc_policy").default_val("RANDOM");
    RAMULATOR_PARSE_PARAM(m_blast_radius, int, "blast_radius").default_val(2);
    RAMULATOR_PARSE_PARAM(m_is_debug, bool, "debug").default_val(false);
  }

  void setup(IFrontEnd* frontend, IMemorySystem* memory_system) override {
    m_ctrl = cast_parent<ControllerBase>();
    auto* spec = m_ctrl->m_device.m_spec;

    m_act_cmd_id = spec->get_command_id("ACT");
    m_prepb_cmd_id = spec->get_command_id("PREpb");
    m_rd_cmd_id = spec->get_command_id("RD");
    m_wr_cmd_id = spec->get_command_id("WR");
    m_rank_level = spec->get_level_id("Rank");
    m_bank_level = spec->get_level_id("Bank");
    m_row_level = spec->get_level_id("Row");
    m_col_level = spec->get_level_id("Column");

    m_num_ranks = spec->get_level_size("Rank");
    int num_banks = m_ctrl->m_device.m_bank_nodes.size();
    m_num_banks_per_rank = num_banks / m_num_ranks;
    m_num_rows_per_bank = spec->get_level_size("Row");
    m_num_cls = spec->get_level_size("Column") / 8;

    m_reset_period_clk = m_reset_period_ns / (spec->get_timing_value("tCK_ps") / 1000.0f);

    m_row_address_bits = std::log2(m_num_rows_per_bank);
    m_bank_address_bits = std::log2(m_num_banks_per_rank);
    m_counter_bits = std::ceil(std::log2(m_tracking_threshold) / 8.0f) * 8;
    m_gct_entries_per_bank = m_num_rows_per_bank / m_row_group_size;
    m_gct_index_bits = std::log2(m_gct_entries_per_bank);
    m_rcc_set_num = m_rcc_num_per_rank / 16;
    m_rcc_index_bits = std::log2(m_rcc_set_num);
    m_rcc_tag_row_bits = m_row_address_bits - m_rcc_index_bits;
    m_rcc_tag_bits = m_rcc_tag_row_bits + m_bank_address_bits;

    m_total_rct_cl_size = m_num_rows_per_bank * m_counter_bits / 512;
    m_total_rct_row_size = std::ceil((float)m_total_rct_cl_size / (float)m_num_cls);
    m_rct_per_row = m_num_cls * 512 / m_counter_bits;
    m_rct_per_cl = 512 / m_counter_bits;
    m_group_rct_cl_size = m_row_group_size * m_counter_bits / 512;

    m_gct.resize(num_banks);
    m_rct.resize(num_banks);
    m_rctct.resize(num_banks);

    m_rcc.resize(m_num_ranks);
    for (int i = 0; i < m_num_ranks; i++) {
      m_rcc[i].resize(m_rcc_set_num);
    }

    m_generator = std::mt19937(1337);
    m_rcc_evict_dist = std::uniform_int_distribution<int>(0, 15);

    m_stats.add("hydra_act_triggers", s_num_triggers);
    m_stats.add("hydra_act_triggers_rct", s_num_triggers_rct);
    m_stats.add("hydra_act_victim_refreshes", s_num_victim_refreshes);
    m_stats.add("hydra_act_dropped", s_num_dropped);
    m_stats.add("hydra_num_read_req", s_num_read_req);
    m_stats.add("hydra_num_write_req", s_num_write_req);
    m_stats.add("hydra_num_initialization", s_num_initialization);
    m_stats.add("hydra_num_eviction", s_num_eviction);
    m_stats.add("hydra_num_rcc_miss", s_num_rcc_miss);
    m_stats.add("hydra_gct_check", s_gct_check);
    m_stats.add("hydra_rcc_check", s_rcc_check);
    m_stats.add("hydra_rct_check", s_rct_check);
    m_stats.add("hydra_rctct_check", s_rctct_check);
  }

  void pre_schedule() override {
    m_clk++;

    if (m_clk % m_reset_period_clk == 0) {
      for (auto& t : m_gct) t.clear();
      for (auto& t : m_rct) t.clear();
      for (auto& t : m_rctct) t.clear();
      for (auto& rank : m_rcc) {
        for (auto& set : rank) {
          set.clear();
        }
      }
    }
  }

  void on_issue(const Request& req) override {
    auto* spec = m_ctrl->m_device.m_spec;

    if (!spec->command_meta[req.command].is_opening) return;
    if (spec->bank_targets[req.command] != BankTarget::Single) return;
    // Bỏ qua ACT làm tươi nạn nhân do chính plugin phát (cùng điều kiện với Q-Shield), vẫn giữ theo dõi ACT của RCT trong RCTCT
    if (req.source_id == kMitigationSourceId) return;

    int row_id = req.addr_vec[m_row_level];
    int flat_bank_id = m_ctrl->m_device.get_flat_bank_id(req.addr_vec);
    int rank_id = req.addr_vec[m_rank_level];
    int bank_id = flat_bank_id % m_num_banks_per_rank;

    int gct_index = row_id >> (m_row_address_bits - m_gct_index_bits);
    int rcc_index = row_id & ((1 << m_rcc_index_bits) - 1);
    int rcc_tag = (row_id >> (m_row_address_bits - m_rcc_tag_row_bits))
                  | (bank_id << m_rcc_tag_row_bits);

    if (row_id < m_total_rct_row_size) {
      if (m_rctct[flat_bank_id].find(row_id) == m_rctct[flat_bank_id].end()) {
        m_rctct[flat_bank_id][row_id] = 0;
      }
      m_rctct[flat_bank_id][row_id]++;
      s_rctct_check++;
      if (m_rctct[flat_bank_id][row_id] >= m_tracking_threshold) {
        issue_victim_act_pre(req.addr_vec);
        s_num_triggers_rct++;
        m_rctct[flat_bank_id].erase(row_id);
      }
      return;
    }

    s_gct_check++;
    auto& gct_entry = m_gct[flat_bank_id][gct_index];

    if (gct_entry.group_count < m_group_threshold) {
      gct_entry.group_count++;
      return;
    }

    if (!gct_entry.initialized) {
      gct_entry.initialized = true;
      s_num_initialization++;
      int row_group_start = gct_index * m_row_group_size;
      for (int i = 0; i < m_row_group_size; i++) {
        m_rct[flat_bank_id][row_group_start + i] = m_group_threshold;
      }
      for (int i = 0; i < m_group_rct_cl_size; i++) {
        int cl_workload_row = row_group_start + i * m_rct_per_cl;
        issue_rct_access(/*is_write=*/true, cl_workload_row, req.addr_vec);
      }
    }

    s_rcc_check++;
    auto& rcc_set = m_rcc[rank_id][rcc_index];
    auto it = rcc_set.find(rcc_tag);
    if (it == rcc_set.end()) {
      s_num_rcc_miss++;
      if (rcc_set.size() == 16) {
        int tag_to_evict = get_tag_to_evict(rank_id, rcc_index);
        auto evict_it = rcc_set.find(tag_to_evict);
        if (evict_it != rcc_set.end()) {
          int evicted_row_id = evict_it->second.row_id;
          issue_rct_access(/*is_write=*/true, evicted_row_id,
                           evict_it->second.addr_template);
          rcc_set.erase(evict_it);
          s_num_eviction++;
        }
      }

      s_rct_check++;
      issue_rct_access(/*is_write=*/false, row_id, req.addr_vec);

      m_rct[flat_bank_id][row_id]++;
      rcc_set[rcc_tag] = RCCEntry{row_id, flat_bank_id,
                                  m_rct[flat_bank_id][row_id],
                                  /*dirty=*/true, req.addr_vec};
      it = rcc_set.find(rcc_tag);
    } else {
      it->second.count++;
      it->second.dirty = true;
      m_rct[flat_bank_id][row_id]++;
    }

    if (it->second.count >= m_tracking_threshold) {
      issue_victim_act_pre(req.addr_vec);
      it->second.count = 0;
      it->second.dirty = true;
      m_rct[flat_bank_id][row_id] = 0;
    }
  }

  void reset_stats() override {
    s_num_triggers = 0;
    s_num_triggers_rct = 0;
    s_num_victim_refreshes = 0;
    s_num_dropped = 0;
    s_num_read_req = 0;
    s_num_write_req = 0;
    s_num_initialization = 0;
    s_num_eviction = 0;
    s_num_rcc_miss = 0;
    s_gct_check = 0;
    s_rcc_check = 0;
    s_rct_check = 0;
    s_rctct_check = 0;
  }

 private:
  void issue_victim_act_pre(const AddrVec_t& aggr_addr) {
    int aggr_row = aggr_addr[m_row_level];
    s_num_triggers++;
    std::vector<int> offsets = {-1, 1};
    if (m_blast_radius >= 2) {
      offsets.push_back(-2);
      offsets.push_back(2);
    }
    for (int d : offsets) {
      int v = aggr_row + d;
      if (v < 0 || v >= m_num_rows_per_bank) continue;
      AddrVec_t v_addr = aggr_addr;
      v_addr[m_row_level] = v;

      Request act_req(v_addr, Request::Cmd, m_act_cmd_id);
      act_req.source_id = kMitigationSourceId;
      Request pre_req(v_addr, Request::Cmd, m_prepb_cmd_id);
      pre_req.source_id = kMitigationSourceId;

      if (m_ctrl->priority_send(act_req)) {
        if (m_ctrl->priority_send(pre_req)) {
          s_num_victim_refreshes++;
        } else {
          s_num_dropped++;
        }
      } else {
        s_num_dropped++;
      }
    }
  }

  std::pair<int, int> generate_row_col_id(int workload_row_id) const {
    int rct_row_id = workload_row_id / m_rct_per_row;
    int rct_col_id = (workload_row_id % m_rct_per_row) * m_counter_bits / 512;
    rct_col_id = rct_col_id << 3;
    return {rct_row_id, rct_col_id};
  }

  void issue_rct_access(bool is_write, int workload_row_id,
                        const AddrVec_t& template_addr_vec) {
    auto [rct_row, rct_col] = generate_row_col_id(workload_row_id);
    AddrVec_t addr = template_addr_vec;
    addr[m_row_level] = rct_row;
    addr[m_col_level] = rct_col;

    Request act_req(addr, Request::Cmd, m_act_cmd_id);
    m_ctrl->priority_send(act_req);

    int col_cmd_id = is_write ? m_wr_cmd_id : m_rd_cmd_id;
    Request col_req(addr, Request::Cmd, col_cmd_id);
    m_ctrl->priority_send(col_req);

    if (is_write) {
      s_num_write_req++;
    } else {
      s_num_read_req++;
    }
  }

  int get_tag_to_evict(int rank_id, int rcc_index) {
    auto& rcc_set = m_rcc[rank_id][rcc_index];
    if (m_rcc_policy == "RANDOM") {
      int idx = m_rcc_evict_dist(m_generator);
      auto it = rcc_set.begin();
      std::advance(it, idx % rcc_set.size());
      return it->first;
    } else if (m_rcc_policy == "MIN_COUNT") {
      int min_count = INT_MAX;
      int min_tag = -1;
      for (auto& [tag, entry] : rcc_set) {
        if (entry.count < min_count) {
          min_count = entry.count;
          min_tag = tag;
        }
      }
      return min_tag;
    }
    throw std::runtime_error("HydraAct: Unknown RCC eviction policy: " + m_rcc_policy);
  }
};

}  // namespace Ramulator
