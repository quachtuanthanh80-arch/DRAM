// File: sim/ramulator2_qshield/src/ramulator/controller/plugin/impl/rh_observer.cpp
// Chức năng: Plugin quan sát thụ động đếm lệnh DRAM và nhiễu RowHammer thực tế trên từng hàng/bank.

#include <algorithm>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "ramulator/base/base.h"
#include "ramulator/base/param.h"
#include "ramulator/controller/controller_base.h"
#include "ramulator/controller/plugin/i_controller_plugin.h"
#include "ramulator/dram/dram_spec.h"

namespace Ramulator {

class RowHammerObserver : public IControllerPlugin, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IControllerPlugin, RowHammerObserver, "RowHammerObserver")

 private:
  ControllerBase* m_ctrl = nullptr;

  int m_n_rh = 1024;
  int m_refw_refs = 8192;

  int m_cmd_act = -1;
  int m_cmd_prepb = -1;
  int m_cmd_preab = -1;
  int m_cmd_rd = -1;
  int m_cmd_wr = -1;
  int m_cmd_rda = -1;
  int m_cmd_wra = -1;
  int m_cmd_refab = -1;
  int m_cmd_vrr = -1;
  int m_cmd_rfmab = -1;
  int m_cmd_rfmsb = -1;

  int m_rank_level = -1;
  int m_row_level = -1;
  int m_num_ranks = 1;
  int m_num_banks = 0;
  int m_num_banks_per_rank = 0;
  int m_num_rows = 0;
  int m_rows_per_ref = 1;

  static constexpr int kMetaSourceId = -77;
  static constexpr int kMitSourceId = -99;

  std::vector<std::unordered_map<int, int>> m_row_acts;
  std::vector<std::unordered_map<int, int>> m_disturb_r1;
  std::vector<std::unordered_map<int, int>> m_disturb_r1_meta;
  std::vector<std::unordered_map<int, int>> m_disturb_r1_mit;
  std::vector<std::unordered_map<int, int>> m_disturb_r1_user;
  std::vector<std::unordered_map<int, int>> m_disturb_r2;
  std::vector<std::unordered_set<int>> m_meta_rows;
  std::vector<std::unordered_set<int>> m_exceeded_r1;
  std::vector<std::unordered_set<int>> m_exceeded_r2;
  std::vector<int> m_ref_row_ptr;

  size_t s_num_act = 0;
  size_t s_num_meta_act = 0;
  size_t s_num_mit_act = 0;
  size_t s_num_pre = 0;
  size_t s_num_rd = 0;
  size_t s_num_wr = 0;
  size_t s_num_refab = 0;
  size_t s_num_vrr = 0;
  size_t s_num_rfmab = 0;
  size_t s_num_rfmsb = 0;
  size_t s_max_row_acts = 0;
  size_t s_max_disturb_r1 = 0;
  size_t s_max_disturb_r2 = 0;
  size_t s_max_r1_bank = 0;
  size_t s_max_r1_row = 0;
  size_t s_max_r1_row_is_meta = 0;
  size_t s_max_r1_aggr_meta_acts = 0;
  size_t s_max_r1_aggr_mit_acts = 0;
  size_t s_max_r1_aggr_user_acts = 0;
  size_t s_rows_exceeding_nrh_r1 = 0;
  size_t s_rows_exceeding_nrh_r2 = 0;

 public:
  void init() override {
    RAMULATOR_PARSE_PARAM(m_n_rh, int, "n_rh").default_val(1024);
    RAMULATOR_PARSE_PARAM(m_refw_refs, int, "refw_refs").default_val(8192);
    if (m_n_rh <= 0) m_n_rh = 1;
    if (m_refw_refs <= 0) m_refw_refs = 8192;
  }

  void setup(IFrontEnd* frontend, IMemorySystem* memory_system) override {
    m_ctrl = cast_parent<ControllerBase>();
    const auto* spec = m_ctrl->m_device.m_spec;

    m_cmd_act = spec->get_command_id("ACT");
    m_cmd_prepb = spec->has_command("PREpb") ? spec->get_command_id("PREpb") : -1;
    m_cmd_preab = spec->has_command("PREab") ? spec->get_command_id("PREab") : -1;
    m_cmd_rd = spec->has_command("RD") ? spec->get_command_id("RD") : -1;
    m_cmd_wr = spec->has_command("WR") ? spec->get_command_id("WR") : -1;
    m_cmd_rda = spec->has_command("RDA") ? spec->get_command_id("RDA") : -1;
    m_cmd_wra = spec->has_command("WRA") ? spec->get_command_id("WRA") : -1;
    m_cmd_refab = spec->has_command("REFab") ? spec->get_command_id("REFab") : -1;
    m_cmd_vrr = spec->has_command("VRR") ? spec->get_command_id("VRR") : -1;
    m_cmd_rfmab = spec->has_command("RFMab") ? spec->get_command_id("RFMab") : -1;
    m_cmd_rfmsb = spec->has_command("RFMsb") ? spec->get_command_id("RFMsb") : -1;

    m_rank_level = spec->has_level("Rank") ? spec->get_level_id("Rank") : -1;
    m_row_level = spec->get_level_id("Row");
    m_num_ranks = (m_rank_level >= 0) ? spec->get_level_size("Rank") : 1;
    m_num_banks = static_cast<int>(m_ctrl->m_device.m_bank_nodes.size());
    m_num_banks_per_rank = (m_num_ranks > 0) ? (m_num_banks / m_num_ranks) : m_num_banks;
    m_num_rows = spec->get_level_size("Row");
    m_rows_per_ref = std::max(1, m_num_rows / m_refw_refs);

    m_row_acts.resize(m_num_banks);
    m_disturb_r1.resize(m_num_banks);
    m_disturb_r1_meta.resize(m_num_banks);
    m_disturb_r1_mit.resize(m_num_banks);
    m_disturb_r1_user.resize(m_num_banks);
    m_disturb_r2.resize(m_num_banks);
    m_meta_rows.resize(m_num_banks);
    m_exceeded_r1.resize(m_num_banks);
    m_exceeded_r2.resize(m_num_banks);
    m_ref_row_ptr.assign(m_num_ranks, 0);

    m_stats.add("obs_num_act", s_num_act);
    m_stats.add("obs_num_meta_act", s_num_meta_act);
    m_stats.add("obs_num_mit_act", s_num_mit_act);
    m_stats.add("obs_num_pre", s_num_pre);
    m_stats.add("obs_num_rd", s_num_rd);
    m_stats.add("obs_num_wr", s_num_wr);
    m_stats.add("obs_num_refab", s_num_refab);
    m_stats.add("obs_num_vrr", s_num_vrr);
    m_stats.add("obs_num_rfmab", s_num_rfmab);
    m_stats.add("obs_num_rfmsb", s_num_rfmsb);
    m_stats.add("obs_max_row_acts", s_max_row_acts);
    m_stats.add("obs_max_disturb_r1", s_max_disturb_r1);
    m_stats.add("obs_max_disturb_r2", s_max_disturb_r2);
    m_stats.add("obs_max_r1_bank", s_max_r1_bank);
    m_stats.add("obs_max_r1_row", s_max_r1_row);
    m_stats.add("obs_max_r1_row_is_meta", s_max_r1_row_is_meta);
    m_stats.add("obs_max_r1_aggr_meta_acts", s_max_r1_aggr_meta_acts);
    m_stats.add("obs_max_r1_aggr_mit_acts", s_max_r1_aggr_mit_acts);
    m_stats.add("obs_max_r1_aggr_user_acts", s_max_r1_aggr_user_acts);
    m_stats.add("obs_rows_exceeding_nrh_r1", s_rows_exceeding_nrh_r1);
    m_stats.add("obs_rows_exceeding_nrh_r2", s_rows_exceeding_nrh_r2);
  }

  void on_issue(const Request& req) override {
    const auto* spec = m_ctrl->m_device.m_spec;
    const int cmd = req.command;

    if (cmd == m_cmd_act) {
      s_num_act++;
    } else if (cmd == m_cmd_prepb || cmd == m_cmd_preab) {
      s_num_pre++;
    } else if (cmd == m_cmd_rd || cmd == m_cmd_rda) {
      s_num_rd++;
    } else if (cmd == m_cmd_wr || cmd == m_cmd_wra) {
      s_num_wr++;
    } else if (cmd == m_cmd_refab) {
      s_num_refab++;
    } else if (cmd == m_cmd_vrr) {
      s_num_vrr++;
    } else if (cmd == m_cmd_rfmab) {
      s_num_rfmab++;
    } else if (cmd == m_cmd_rfmsb) {
      s_num_rfmsb++;
    }

    if (spec->command_meta[cmd].is_opening &&
        spec->bank_targets[cmd] == BankTarget::Single &&
        !req.addr_vec.empty()) {
      int bank = m_ctrl->m_device.get_flat_bank_id(req.addr_vec);
      int row = req.addr_vec[m_row_level];
      if (bank < 0 || bank >= m_num_banks || row < 0 || row >= m_num_rows) {
        return;
      }

      int& act_cnt = m_row_acts[bank][row];
      act_cnt++;
      if (static_cast<size_t>(act_cnt) > s_max_row_acts) {
        s_max_row_acts = static_cast<size_t>(act_cnt);
      }

      const bool is_meta_act = (req.source_id == kMetaSourceId);
      const bool is_mit_act = (req.source_id == kMitSourceId);
      if (is_meta_act) {
        s_num_meta_act++;
        m_meta_rows[bank].insert(row);
      } else if (is_mit_act) {
        s_num_mit_act++;
      }

      // Activating a row physically refreshes that row's cell charge
      m_disturb_r1[bank][row] = 0;
      m_disturb_r1_meta[bank][row] = 0;
      m_disturb_r1_mit[bank][row] = 0;
      m_disturb_r1_user[bank][row] = 0;
      m_disturb_r2[bank][row] = 0;

      for (int d : {-1, 1}) {
        int v = row + d;
        if (v >= 0 && v < m_num_rows) {
          int& dv = m_disturb_r1[bank][v];
          dv++;
          if (is_meta_act) {
            m_disturb_r1_meta[bank][v]++;
          } else if (is_mit_act) {
            m_disturb_r1_mit[bank][v]++;
          } else {
            m_disturb_r1_user[bank][v]++;
          }
          if (static_cast<size_t>(dv) > s_max_disturb_r1) {
            s_max_disturb_r1 = static_cast<size_t>(dv);
            s_max_r1_bank = static_cast<size_t>(bank);
            s_max_r1_row = static_cast<size_t>(v);
            s_max_r1_row_is_meta = m_meta_rows[bank].count(v) ? 1u : 0u;
            s_max_r1_aggr_meta_acts = static_cast<size_t>(m_disturb_r1_meta[bank][v]);
            s_max_r1_aggr_mit_acts = static_cast<size_t>(m_disturb_r1_mit[bank][v]);
            s_max_r1_aggr_user_acts = static_cast<size_t>(m_disturb_r1_user[bank][v]);
          }
          if (dv >= m_n_rh && m_exceeded_r1[bank].insert(v).second) {
            s_rows_exceeding_nrh_r1++;
          }
        }
      }

      for (int d : {-2, -1, 1, 2}) {
        int v = row + d;
        if (v >= 0 && v < m_num_rows) {
          int& dv = m_disturb_r2[bank][v];
          dv++;
          if (static_cast<size_t>(dv) > s_max_disturb_r2) {
            s_max_disturb_r2 = static_cast<size_t>(dv);
          }
          if (dv >= m_n_rh && m_exceeded_r2[bank].insert(v).second) {
            s_rows_exceeding_nrh_r2++;
          }
        }
      }
      return;
    }

    if (cmd == m_cmd_vrr && !req.addr_vec.empty()) {
      int bank = m_ctrl->m_device.get_flat_bank_id(req.addr_vec);
      int row = req.addr_vec[m_row_level];
      if (bank < 0 || bank >= m_num_banks || row < 0 || row >= m_num_rows) {
        return;
      }
      for (int d : {-1, 1}) {
        int v = row + d;
        if (v >= 0 && v < m_num_rows) {
          m_disturb_r1[bank][v] = 0;
          m_disturb_r1_meta[bank][v] = 0;
          m_disturb_r1_mit[bank][v] = 0;
          m_disturb_r1_user[bank][v] = 0;
        }
      }
      for (int d : {-2, -1, 1, 2}) {
        int v = row + d;
        if (v >= 0 && v < m_num_rows) {
          m_disturb_r2[bank][v] = 0;
        }
      }
      return;
    }

    if (cmd == m_cmd_refab) {
      int rank = (m_rank_level >= 0 && !req.addr_vec.empty() && req.addr_vec[m_rank_level] >= 0)
                     ? req.addr_vec[m_rank_level]
                     : 0;
      if (rank < 0 || rank >= m_num_ranks) return;
      int ptr = m_ref_row_ptr[rank];
      int bank_start = rank * m_num_banks_per_rank;
      int bank_end = std::min(m_num_banks, bank_start + m_num_banks_per_rank);
      for (int k = 0; k < m_rows_per_ref; k++) {
        int r = (ptr + k) % m_num_rows;
        for (int b = bank_start; b < bank_end; b++) {
          m_disturb_r1[b].erase(r);
          m_disturb_r1_meta[b].erase(r);
          m_disturb_r1_mit[b].erase(r);
          m_disturb_r1_user[b].erase(r);
          m_disturb_r2[b].erase(r);
          m_row_acts[b].erase(r);
        }
      }
      m_ref_row_ptr[rank] = (ptr + m_rows_per_ref) % m_num_rows;
    }
  }

  void reset_stats() override {
    s_num_act = 0;
    s_num_meta_act = 0;
    s_num_mit_act = 0;
    s_num_pre = 0;
    s_num_rd = 0;
    s_num_wr = 0;
    s_num_refab = 0;
    s_num_vrr = 0;
    s_num_rfmab = 0;
    s_num_rfmsb = 0;
    s_max_row_acts = 0;
    s_max_disturb_r1 = 0;
    s_max_disturb_r2 = 0;
    s_max_r1_bank = 0;
    s_max_r1_row = 0;
    s_max_r1_row_is_meta = 0;
    s_max_r1_aggr_meta_acts = 0;
    s_max_r1_aggr_mit_acts = 0;
    s_max_r1_aggr_user_acts = 0;
    s_rows_exceeding_nrh_r1 = 0;
    s_rows_exceeding_nrh_r2 = 0;
  }
};

}  // namespace Ramulator
