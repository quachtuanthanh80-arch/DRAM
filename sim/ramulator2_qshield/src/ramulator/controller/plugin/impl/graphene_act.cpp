// File: sim/ramulator2_qshield/src/ramulator/controller/plugin/impl/graphene_act.cpp
// Chức năng: Biến thể Graphene cho DRAM thương mại (không dùng VRR), làm tươi nạn nhân bán kính R bằng ACT + PREpb chuẩn JEDEC.
// Adapted from CMU-SAFARI/ramulator2 (commit 72427a1, MIT License) src/ramulator/controller/plugin/impl/graphene.cpp.

#include <iostream>
#include <stdexcept>
#include <unordered_map>
#include <vector>

#include "ramulator/base/base.h"
#include "ramulator/base/param.h"
#include "ramulator/controller/controller_base.h"
#include "ramulator/controller/plugin/i_controller_plugin.h"
#include "ramulator/dram/dram_spec.h"

namespace Ramulator {

class GrapheneAct : public IControllerPlugin, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IControllerPlugin, GrapheneAct, "GrapheneAct")

 private:
  static constexpr int kMitigationSourceId = -99;

  ControllerBase* m_ctrl = nullptr;

  int m_clk = 0;

  int m_num_table_entries = -1;
  int m_activation_threshold = -1;
  int m_reset_period_ns = -1;
  int m_reset_period_clk = -1;
  int m_blast_radius = 2;
  bool m_is_debug = false;

  int m_act_cmd_id = -1;
  int m_prepb_cmd_id = -1;
  int m_rank_level = -1;
  int m_bank_level = -1;
  int m_row_level = -1;
  int m_num_rows_per_bank = -1;

  std::vector<std::unordered_map<int, int>> m_activation_count_table;
  std::vector<int> m_spillover_counter;

  size_t s_num_triggers = 0;
  size_t s_num_victim_refreshes = 0;
  size_t s_num_dropped = 0;

 public:
  void init() override {
    RAMULATOR_PARSE_PARAM(m_num_table_entries, int, "num_table_entries").required();
    RAMULATOR_PARSE_PARAM(m_activation_threshold, int, "activation_threshold").required();
    RAMULATOR_PARSE_PARAM(m_reset_period_ns, int, "reset_period_ns").required();
    RAMULATOR_PARSE_PARAM(m_blast_radius, int, "blast_radius").default_val(2);
    RAMULATOR_PARSE_PARAM(m_is_debug, bool, "debug").default_val(false);
  }

  void setup(IFrontEnd* frontend, IMemorySystem* memory_system) override {
    m_ctrl = cast_parent<ControllerBase>();
    auto* spec = m_ctrl->m_device.m_spec;

    m_reset_period_clk = m_reset_period_ns / ((float)spec->get_timing_value("tCK_ps") / 1000.0f);

    m_act_cmd_id = spec->get_command_id("ACT");
    m_prepb_cmd_id = spec->get_command_id("PREpb");
    m_rank_level = spec->get_level_id("Rank");
    m_bank_level = spec->get_level_id("Bank");
    m_row_level = spec->get_level_id("Row");

    int num_banks = m_ctrl->m_device.m_bank_nodes.size();
    m_num_rows_per_bank = spec->get_level_size("Row");

    for (int i = 0; i < num_banks; i++) {
      std::unordered_map<int, int> table;
      for (int j = -m_num_rows_per_bank; j < -m_num_rows_per_bank + m_num_table_entries; j++) {
        table[j] = 0;
      }
      m_activation_count_table.push_back(table);
    }

    m_spillover_counter.assign(num_banks, 0);

    m_stats.add("graphene_act_triggers", s_num_triggers);
    m_stats.add("graphene_act_victim_refreshes", s_num_victim_refreshes);
    m_stats.add("graphene_act_dropped", s_num_dropped);
  }

  void pre_schedule() override {
    m_clk++;

    if (m_clk % m_reset_period_clk == 0) {
      for (size_t i = 0; i < m_activation_count_table.size(); i++) {
        for (auto& [row_id, count] : m_activation_count_table[i]) {
          count = 0;
        }
        m_spillover_counter[i] = 0;
      }
    }
  }

  void on_issue(const Request& req) override {
    auto* spec = m_ctrl->m_device.m_spec;

    if (!spec->command_meta[req.command].is_opening) return;
    if (spec->bank_targets[req.command] != BankTarget::Single) return;
    // Không đếm lại ACT làm tươi nạn nhân do chính plugin phát (cùng điều kiện với Q-Shield)
    if (req.source_id == kMitigationSourceId) return;

    int bank_id = m_ctrl->m_device.get_flat_bank_id(req.addr_vec);
    int row_id = req.addr_vec[m_row_level];

    auto it = m_activation_count_table[bank_id].find(row_id);
    if (it == m_activation_count_table[bank_id].end()) {
      bool found = false;
      int to_remove = -1;
      int spillover_value = -1;

      for (auto& [rid, count] : m_activation_count_table[bank_id]) {
        if (count == m_spillover_counter[bank_id]) {
          spillover_value = count;
          to_remove = rid;
          found = true;
          break;
        }
      }

      if (found) {
        m_activation_count_table[bank_id].erase(to_remove);
        m_activation_count_table[bank_id][row_id] = spillover_value + 1;
      } else {
        m_spillover_counter[bank_id]++;
      }
    } else {
      it->second++;
      if (it->second >= m_activation_threshold) {
        issue_victim_act_pre(req.addr_vec);
        it->second = m_spillover_counter[bank_id];
      }
    }
  }

  void reset_stats() override {
    s_num_triggers = 0;
    s_num_victim_refreshes = 0;
    s_num_dropped = 0;
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
};

}  // namespace Ramulator
