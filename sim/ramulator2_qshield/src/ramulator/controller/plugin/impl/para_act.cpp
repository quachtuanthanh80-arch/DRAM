// File: sim/ramulator2_qshield/src/ramulator/controller/plugin/impl/para_act.cpp
// Chức năng: Biến thể PARA cho DRAM thương mại (không dùng VRR), làm tươi nạn nhân bán kính R bằng ACT + PREpb chuẩn JEDEC.
// Adapted from CMU-SAFARI/ramulator2 (commit 72427a1, MIT License) src/ramulator/controller/plugin/impl/para.cpp.

#include <iostream>
#include <random>
#include <stdexcept>
#include <vector>

#include "ramulator/base/base.h"
#include "ramulator/base/param.h"
#include "ramulator/controller/controller_base.h"
#include "ramulator/controller/plugin/i_controller_plugin.h"
#include "ramulator/dram/dram_spec.h"

namespace Ramulator {

class ParaAct : public IControllerPlugin, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IControllerPlugin, ParaAct, "ParaAct")

 private:
  static constexpr int kMitigationSourceId = -99;

  ControllerBase* m_ctrl = nullptr;

  float m_pr_threshold = 0.0f;
  int m_seed = 123;
  int m_blast_radius = 2;
  bool m_is_debug = false;

  std::mt19937 m_generator;
  std::uniform_real_distribution<float> m_distribution;

  int m_act_cmd_id = -1;
  int m_prepb_cmd_id = -1;
  int m_row_level = -1;
  int m_num_rows_per_bank = 0;

  size_t s_num_triggers = 0;
  size_t s_num_victim_refreshes = 0;
  size_t s_num_dropped = 0;

 public:
  void init() override {
    RAMULATOR_PARSE_PARAM(m_pr_threshold, float, "threshold").required();
    if (m_pr_threshold <= 0.0f || m_pr_threshold >= 1.0f) {
      throw std::runtime_error("ParaAct: Invalid probability threshold!");
    }
    RAMULATOR_PARSE_PARAM(m_seed, int, "seed").default_val(123);
    RAMULATOR_PARSE_PARAM(m_blast_radius, int, "blast_radius").default_val(2);
    RAMULATOR_PARSE_PARAM(m_is_debug, bool, "debug").default_val(false);

    m_generator = std::mt19937(m_seed);
    m_distribution = std::uniform_real_distribution<float>(0.0, 1.0);
  }

  void setup(IFrontEnd* frontend, IMemorySystem* memory_system) override {
    m_ctrl = cast_parent<ControllerBase>();
    auto* spec = m_ctrl->m_device.m_spec;

    m_act_cmd_id = spec->get_command_id("ACT");
    m_prepb_cmd_id = spec->get_command_id("PREpb");
    m_row_level = spec->get_level_id("Row");
    m_num_rows_per_bank = spec->get_level_size("Row");

    m_stats.add("para_act_triggers", s_num_triggers);
    m_stats.add("para_act_victim_refreshes", s_num_victim_refreshes);
    m_stats.add("para_act_dropped", s_num_dropped);
  }

  void on_issue(const Request& req) override {
    auto* spec = m_ctrl->m_device.m_spec;
    if (!spec->command_meta[req.command].is_opening) return;
    if (spec->bank_targets[req.command] != BankTarget::Single) return;
    // Không đếm lại ACT làm tươi nạn nhân do chính plugin phát (cùng điều kiện với Q-Shield)
    if (req.source_id == kMitigationSourceId) return;
    if (m_distribution(m_generator) >= m_pr_threshold) return;

    issue_victim_act_pre(req.addr_vec);
    if (m_is_debug) {
      std::cout << "ParaAct: ACT+PREpb victim refresh fired" << std::endl;
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
