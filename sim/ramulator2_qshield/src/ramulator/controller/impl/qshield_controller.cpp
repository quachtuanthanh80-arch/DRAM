// File: sim/ramulator2_qshield/src/ramulator/controller/impl/qshield_controller.cpp
// Chức năng: Mô hình bộ điều khiển Q-Shield khớp RTL (SDC-Resilient Filter, PXOR, DRM PROQ, RFM tự trị, RowPress/tRAS_max và BMT/MAC cache).

#include <algorithm>
#include <cstdint>
#include <deque>
#include <list>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

#include "ramulator/base/base.h"
#include "ramulator/base/param.h"
#include "ramulator/controller/controller_base.h"
#include "ramulator/controller/refresh/i_refresh_manager.h"
#include "ramulator/controller/rowpolicy/i_row_policy.h"
#include "ramulator/dram/dram_spec.h"

namespace Ramulator {

class QShieldController : public ControllerBase {
  RAMULATOR_REGISTER_IMPLEMENTATION_DERIVED(IController, QShieldController, ControllerBase, "QShield")

 private:
  // RTL-mapped parameters (parsed in init)
  int m_sdc_thresh = 127;
  int m_table_entries = 256;
  bool m_dual_hash_en = true;
  bool m_pxor_mode = true;
  std::string m_pxor_seed_hex = "A5A55A5A01234567";
  int m_refw_refs = 8192;
  int m_window_size_ctrl_cycles = 4096;
  int m_multibank_thresh = 2;
  int m_blast_radius = 2;
  int m_proq_depth = 32;
  int m_throttle_pace_clk = 80;
  int m_raammt_thresh = 32;
  int m_tras_max_ns = 21937;
  int m_rowpress_thresh_ns = 12500;
  int m_rowpress_curve = 0;

  bool m_integrity_en = false;
  int m_mc_sets = 16;
  int m_mc_ways = 4;
  int m_prot_lines = 1048576;
  int m_tree_levels = 4;
  int m_crypto_extra_lat_clk = 84;
  bool m_debug = false;

  // Tham số hiệu chuẩn RTL tùy chọn cho T81 (mặc định giữ nguyên hành vi T80)
  int m_dq_cas_gap_rd_rd_clk = 0;
  int m_dq_cas_gap_wr_wr_clk = 0;
  int m_dq_cas_gap_rd_wr_clk = 0;
  int m_dq_cas_gap_wr_rd_clk = 0;
  int m_rtl_rd_extra_lat_clk = 0;
  bool m_disable_wr_coalesce = false;
  bool m_sdc_count_requests = false;
  int m_scrub_interval_ctrl_cycles = 0;
  int m_ref_postpone_max = 0;
  bool m_rtl_integrity_mode = false;
  bool m_rtl_ml_reenc_ack_overlap = false;
  // Mặc định false = khớp RTL (truy cập metadata AXI id[3]=1 đi qua u_sdc_filter & u_drm)
  bool m_meta_bypass_drm = false;

  // Derived constants
  uint64_t m_pxor_seed = 0xA5A55A5A01234567ULL;
  uint32_t m_pxor_mask_a[8] = {0};
  uint32_t m_pxor_mask_b[8] = {0};
  int m_ctrl_ratio = 4;  // DFI 1:4 -> 1 ctrl cycle (2.5ns @ 400MHz) ~= 4 DDR5-3200 CK (625ps)
  Clk_t m_window_size_dram_clk = 16384;
  int m_tras_max_ctrl_cyc = 8775;
  int m_rp_base_ctrl_cyc = 5000;
  Clk_t m_next_rd_cas_clk = 0;
  Clk_t m_next_wr_cas_clk = 0;

  // Sentinel 64-bit khớp QShieldTrace để xả ống và chạy T38
  static constexpr uint64_t SENTINEL_DRAIN = 0x7000000000000000ULL;
  static constexpr uint64_t SENTINEL_META_INIT = 0x7000000000000001ULL;
  static constexpr uint64_t SENTINEL_META_FLUSH = 0x7000000000000002ULL;
  static constexpr uint64_t SENTINEL_CACHE_CLEAR = 0x7000000000000003ULL;
  static constexpr uint64_t SENTINEL_FORCE_MINOR_MASK = 0x7100000000000000ULL;
  static constexpr uint64_t SENTINEL_BMT_FAIL_MASK = 0x7200000000000000ULL;

  // Spec lookups
  int m_cmd_act = -1;
  int m_cmd_prepb = -1;
  int m_cmd_rd = -1;
  int m_cmd_rda = -1;
  int m_cmd_wr = -1;
  int m_cmd_wra = -1;
  int m_cmd_refab = -1;
  int m_cmd_rfmab = -1;
  int m_rank_level = -1;
  int m_bg_level = -1;
  int m_row_level = -1;
  int m_num_ranks = 1;
  int m_num_bgs_per_rank = 8;
  int m_num_banks_per_bg = 4;
  int m_num_banks = 32;
  int m_num_banks_per_rank = 32;
  int m_num_rows = 65536;
  uint64_t m_channel_cap_bytes = 1ULL << 30;

  // SDC Resilient Filter state
  std::vector<uint16_t> m_table_a_cnt;
  std::vector<uint8_t> m_table_a_epoch;
  std::vector<uint16_t> m_table_b_cnt;
  std::vector<uint8_t> m_table_b_epoch;
  uint8_t m_current_epoch = 0;
  int m_ref_cnt = 0;
  Clk_t m_window_timer = 0;
  uint32_t m_phys_bank_throttled_flags = 0;  // 32 physical banks {bg, bank}
  bool m_coordinated_throttle_active = false;
  std::vector<std::unordered_map<int, Clk_t>> m_row_cooldown;

  // DRM Alert FIFO + PROQ
  struct AggressorAlert {
    int bank = 0;
    int row = 0;
    bool from_rowpress = false;
    AddrVec_t addr_vec;
  };
  struct ProqEntry {
    int bank = 0;
    int row = 0;
    bool from_rowpress = false;
    AddrVec_t addr_vec;
  };
  std::deque<AggressorAlert> m_alert_fifo;
  std::deque<ProqEntry> m_proq;

  // Per-bank state for victim refresh, RowPress, and tRAS_max clamp
  std::vector<int> m_bank_open_row;
  std::vector<Clk_t> m_bank_open_clk;
  std::vector<bool> m_rp_alerted;
  std::vector<bool> m_tras_clamp_pending;
  std::vector<bool> m_victim_close_req;
  // Giữ chỗ bank từ lúc phát PREpb cho tới khi ACT giảm thiểu kịp phát (tránh user FRFCFS cướp bank)
  std::vector<bool> m_mit_act_reserved;
  std::vector<AddrVec_t> m_bank_addr_templates;

  // Autonomous RFM state per rank/BG
  std::vector<std::vector<int>> m_rolling_act_cnt;
  std::vector<bool> m_rfm_pending;

  // Integrity Metadata Cache + BMT + minor rollover model
  struct McLine {
    bool valid = false;
    bool dirty = false;
    uint64_t addr = 0;
    uint8_t level = 0;  // 0=CB, 1..4=TN, 5=ML
    uint64_t idx = 0;
  };
  struct McSet {
    std::vector<McLine> ways;
    uint8_t plru = 0;
  };
  std::vector<McSet> m_mc;

  // ML Cache tách riêng (4 sets x 2 ways, PLRU 1-bit) và ml_dram_inited cho chế độ khớp RTL
  struct MlLine {
    bool valid = false;
    bool dirty = false;
    uint64_t idx = 0;
    uint64_t addr = 0;
  };
  struct MlSet {
    MlLine ways[2];
    uint8_t plru = 0;
  };
  std::vector<MlSet> m_ml_cache;
  std::vector<bool> m_ml_dram_inited;

  // Hàng đợi hoãn REFab (MAX_POSTPONE) và tuần tra ECC tự trị
  int m_ref_owed_cnt = 0;
  int m_ref_drain_target_owed = 0;
  bool m_refab_dispatched = false;
  bool m_ref_drain_active = false;
  bool m_scrub_armed_by_ref = false;
  Clk_t m_next_ref_allowed_clk = 0;
  Clk_t m_last_scrub_act_clk = 0;
  std::deque<Request> m_deferred_refab_reqs;
  int m_scrub_timer_clk = 0;
  bool m_scrub_pending = false;
  int m_scrub_bg = 0;
  int m_scrub_bank = 0;
  int m_scrub_row = 0;
  int m_drm_consec_grants = 0;

  std::unordered_map<uint64_t, uint8_t> m_minor_cnt;
  ReqBuffer m_meta_rd_buffer;
  ReqBuffer m_meta_wb_buffer;
  uint64_t m_meta_base = 0;
  uint64_t m_ml_base = 0;
  uint64_t m_tn_base = 0;
  std::vector<uint64_t> m_tn_offsets;

  // Stats
  size_t s_sdc_throttles = 0;
  size_t s_coordinated_throttles = 0;
  size_t s_victim_refreshes = 0;
  size_t s_mit_acts = 0;
  size_t s_traffic_acts = 0;
  size_t s_ref_count = 0;
  size_t s_scrub_acts = 0;
  size_t s_rfm_count = 0;
  size_t s_rowpress_alerts = 0;
  size_t s_tras_clamps = 0;
  size_t s_proq_blocks = 0;
  size_t s_pace_defers = 0;
  size_t s_mc_hits = 0;
  size_t s_mc_misses = 0;
  size_t s_meta_rd_cnt = 0;
  size_t s_meta_wr_cnt = 0;
  size_t s_reencrypt_events = 0;

 public:
  void init() override {
    init_base();

    RAMULATOR_PARSE_PARAM(m_sdc_thresh, int, "sdc_thresh").default_val(127);
    RAMULATOR_PARSE_PARAM(m_table_entries, int, "table_entries").default_val(256);
    RAMULATOR_PARSE_PARAM(m_dual_hash_en, bool, "dual_hash_en").default_val(true);
    RAMULATOR_PARSE_PARAM(m_pxor_mode, bool, "pxor_mode").default_val(true);
    RAMULATOR_PARSE_PARAM(m_pxor_seed_hex, std::string, "pxor_seed_hex").default_val("A5A55A5A01234567");
    RAMULATOR_PARSE_PARAM(m_refw_refs, int, "refw_refs").default_val(8192);
    RAMULATOR_PARSE_PARAM(m_window_size_ctrl_cycles, int, "window_size_ctrl_cycles").default_val(4096);
    RAMULATOR_PARSE_PARAM(m_multibank_thresh, int, "multibank_thresh").default_val(2);
    RAMULATOR_PARSE_PARAM(m_blast_radius, int, "blast_radius").default_val(2);
    RAMULATOR_PARSE_PARAM(m_proq_depth, int, "proq_depth").default_val(32);
    RAMULATOR_PARSE_PARAM(m_throttle_pace_clk, int, "throttle_pace_clk").default_val(80);
    RAMULATOR_PARSE_PARAM(m_raammt_thresh, int, "raammt_thresh").default_val(32);
    RAMULATOR_PARSE_PARAM(m_tras_max_ns, int, "tras_max_ns").default_val(21937);
    RAMULATOR_PARSE_PARAM(m_rowpress_thresh_ns, int, "rowpress_thresh_ns").default_val(12500);
    RAMULATOR_PARSE_PARAM(m_rowpress_curve, int, "rowpress_curve").default_val(0);

    RAMULATOR_PARSE_PARAM(m_integrity_en, bool, "integrity_en").default_val(false);
    RAMULATOR_PARSE_PARAM(m_mc_sets, int, "mc_sets").default_val(16);
    RAMULATOR_PARSE_PARAM(m_mc_ways, int, "mc_ways").default_val(4);
    RAMULATOR_PARSE_PARAM(m_prot_lines, int, "prot_lines").default_val(1048576);
    RAMULATOR_PARSE_PARAM(m_tree_levels, int, "tree_levels").default_val(4);
    RAMULATOR_PARSE_PARAM(m_crypto_extra_lat_clk, int, "crypto_extra_lat_clk").default_val(84);
    RAMULATOR_PARSE_PARAM(m_debug, bool, "debug").default_val(false);
    RAMULATOR_PARSE_PARAM(m_dq_cas_gap_rd_rd_clk, int, "dq_cas_gap_rd_rd_clk").default_val(0);
    RAMULATOR_PARSE_PARAM(m_dq_cas_gap_wr_wr_clk, int, "dq_cas_gap_wr_wr_clk").default_val(0);
    RAMULATOR_PARSE_PARAM(m_dq_cas_gap_rd_wr_clk, int, "dq_cas_gap_rd_wr_clk").default_val(0);
    RAMULATOR_PARSE_PARAM(m_dq_cas_gap_wr_rd_clk, int, "dq_cas_gap_wr_rd_clk").default_val(0);
    RAMULATOR_PARSE_PARAM(m_rtl_rd_extra_lat_clk, int, "rtl_rd_extra_lat_clk").default_val(0);
    RAMULATOR_PARSE_PARAM(m_disable_wr_coalesce, bool, "disable_wr_coalesce").default_val(false);
    RAMULATOR_PARSE_PARAM(m_sdc_count_requests, bool, "sdc_count_requests").default_val(false);
    RAMULATOR_PARSE_PARAM(m_scrub_interval_ctrl_cycles, int, "scrub_interval_ctrl_cycles").default_val(0);
    RAMULATOR_PARSE_PARAM(m_ref_postpone_max, int, "ref_postpone_max").default_val(0);
    RAMULATOR_PARSE_PARAM(m_rtl_integrity_mode, bool, "rtl_integrity_mode").default_val(false);
    RAMULATOR_PARSE_PARAM(m_rtl_ml_reenc_ack_overlap, bool, "rtl_ml_reenc_ack_overlap").default_val(false);
    RAMULATOR_PARSE_PARAM(m_meta_bypass_drm, bool, "meta_bypass_drm").default_val(false);

    if (m_table_entries <= 0) m_table_entries = 256;
    if (m_refw_refs <= 0) m_refw_refs = 8192;
    if (m_proq_depth <= 0) m_proq_depth = 32;
    if (m_mc_sets <= 0) m_mc_sets = 16;
    if (m_mc_ways != 4) m_mc_ways = 4;  // 3-bit Tree-PLRU matches qshield_meta_cache.sv
    if (m_prot_lines < 64) m_prot_lines = 64;

    m_pxor_seed = std::stoull(m_pxor_seed_hex, nullptr, 16);
    if (m_pxor_seed == 0ULL) {
      m_pxor_seed = 0xA5A55A5A01234567ULL;
    }
    init_pxor_masks();
  }

  void setup(IFrontEnd* frontend, IMemorySystem* memory_system) override {
    setup_base(frontend, memory_system);

    const auto* spec = m_device.m_spec;
    m_cmd_act = spec->get_command_id("ACT");
    m_cmd_prepb = spec->get_command_id("PREpb");
    m_cmd_rd = spec->get_command_id("RD");
    m_cmd_rda = spec->has_command("RDA") ? spec->get_command_id("RDA") : -1;
    m_cmd_wr = spec->get_command_id("WR");
    m_cmd_wra = spec->has_command("WRA") ? spec->get_command_id("WRA") : -1;
    m_cmd_refab = spec->has_command("REFab") ? spec->get_command_id("REFab") : -1;
    m_cmd_rfmab = spec->has_command("RFMab") ? spec->get_command_id("RFMab") : -1;

    m_rank_level = spec->has_level("Rank") ? spec->get_level_id("Rank") : -1;
    m_bg_level = spec->has_level("BankGroup") ? spec->get_level_id("BankGroup") : -1;
    m_row_level = spec->get_level_id("Row");

    m_num_ranks = (m_rank_level >= 0) ? spec->get_level_size("Rank") : 1;
    m_num_bgs_per_rank = (m_bg_level >= 0) ? spec->get_level_size("BankGroup") : 1;
    m_num_banks_per_bg = spec->get_level_size("Bank");
    m_num_banks = static_cast<int>(m_device.m_bank_nodes.size());
    m_num_banks_per_rank = (m_num_ranks > 0) ? (m_num_banks / m_num_ranks) : m_num_banks;
    m_num_rows = spec->get_level_size("Row");

    // Approximate channel capacity in bytes for wrapping metadata addresses into valid physical range
    int col_count = spec->get_level_size("Column");
    int prefetch = std::max(1, spec->internal_prefetch_size);
    int tx_bytes = std::max(1, spec->get_tx_bytes());
    m_channel_cap_bytes = static_cast<uint64_t>(m_num_banks) *
                          static_cast<uint64_t>(m_num_rows) *
                          static_cast<uint64_t>(std::max(1, col_count / prefetch)) *
                          static_cast<uint64_t>(tx_bytes);
    if (m_channel_cap_bytes == 0) {
      m_channel_cap_bytes = 1ULL << 30;
    }

    float tck_ns = static_cast<float>(m_tCK_ps) / 1000.0f;
    m_ctrl_ratio = std::max(1, static_cast<int>(2.5f / tck_ns + 0.5f));
    m_window_size_dram_clk = static_cast<Clk_t>(m_window_size_ctrl_cycles) * m_ctrl_ratio;
    m_tras_max_ctrl_cyc = (m_tras_max_ns > 0) ? std::max(1, static_cast<int>(m_tras_max_ns / 2.5)) : 0;
    m_rp_base_ctrl_cyc = (m_rowpress_thresh_ns > 0) ? std::max(1, static_cast<int>(m_rowpress_thresh_ns / 2.5)) : 0;

    m_table_a_cnt.assign(m_table_entries, 0);
    m_table_a_epoch.assign(m_table_entries, 0);
    m_table_b_cnt.assign(m_table_entries, 0);
    m_table_b_epoch.assign(m_table_entries, 0);
    m_row_cooldown.resize(m_num_banks);

    m_bank_open_row.assign(m_num_banks, -1);
    m_bank_open_clk.assign(m_num_banks, 0);
    m_rp_alerted.assign(m_num_banks, false);
    m_tras_clamp_pending.assign(m_num_banks, false);
    m_victim_close_req.assign(m_num_banks, false);
    m_mit_act_reserved.assign(m_num_banks, false);

    m_bank_addr_templates.resize(m_num_banks);
    for (int b = 0; b < m_num_banks; b++) {
      AddrVec_t vec(spec->level_count, 0);
      for (auto* n = m_device.m_bank_nodes[b]; n != nullptr; n = n->m_parent_node) {
        vec[n->m_level] = n->m_node_id;
      }
      vec[0] = m_channel_id;
      m_bank_addr_templates[b] = std::move(vec);
    }

    m_rolling_act_cnt.assign(m_num_ranks, std::vector<int>(m_num_bgs_per_rank, 0));
    m_rfm_pending.assign(m_num_ranks, false);

    m_mc.resize(m_mc_sets);
    for (auto& s : m_mc) {
      s.ways.resize(m_mc_ways);
      s.plru = 0;
    }
    m_ml_cache.resize(4);
    m_ml_dram_inited.assign(static_cast<size_t>(std::max(1, m_prot_lines / 8)), false);
    m_meta_rd_buffer.max_size = 512;
    m_meta_wb_buffer.max_size = 512;

    uint64_t num_cb = static_cast<uint64_t>(m_prot_lines) / 64ULL;
    uint64_t num_ml = static_cast<uint64_t>(m_prot_lines) / 8ULL;
    m_meta_base = static_cast<uint64_t>(m_prot_lines) * 64ULL;
    m_ml_base = m_meta_base + num_cb * 64ULL;
    m_tn_base = m_ml_base + num_ml * 64ULL;
    m_tn_offsets.clear();
    uint64_t off = 0;
    uint64_t lvl_nodes = num_cb / 8ULL;
    for (int lvl = 1; lvl <= m_tree_levels; lvl++) {
      m_tn_offsets.push_back(off);
      off += lvl_nodes;
      lvl_nodes = (lvl_nodes > 8ULL) ? (lvl_nodes / 8ULL) : ((lvl_nodes > 1ULL) ? (lvl_nodes / 8ULL) : 0ULL);
    }

    m_stats.add("qshield_sdc_throttles", s_sdc_throttles);
    m_stats.add("qshield_coordinated_throttles", s_coordinated_throttles);
    m_stats.add("qshield_victim_refreshes", s_victim_refreshes);
    m_stats.add("qshield_mit_acts", s_mit_acts);
    m_stats.add("qshield_traffic_acts", s_traffic_acts);
    m_stats.add("qshield_ref_count", s_ref_count);
    m_stats.add("qshield_scrub_acts", s_scrub_acts);
    m_stats.add("qshield_rfm_count", s_rfm_count);
    m_stats.add("qshield_rowpress_alerts", s_rowpress_alerts);
    m_stats.add("qshield_tras_clamps", s_tras_clamps);
    m_stats.add("qshield_proq_blocks", s_proq_blocks);
    m_stats.add("qshield_pace_defers", s_pace_defers);
    m_stats.add("qshield_mc_hits", s_mc_hits);
    m_stats.add("qshield_mc_misses", s_mc_misses);
    m_stats.add("qshield_meta_rd_cnt", s_meta_rd_cnt);
    m_stats.add("qshield_meta_wr_cnt", s_meta_wr_cnt);
    m_stats.add("qshield_reencrypt_events", s_reencrypt_events);
  }

  bool priority_send(Request& req) override {
    if (m_ref_postpone_max > 0 && m_cmd_refab >= 0 && req.final_command == m_cmd_refab) {
      m_deferred_refab_reqs.push_back(req);
      m_ref_owed_cnt++;
      return true;
    }
    return ControllerBase::priority_send(req);
  }

  bool send(Request& req) override {
    uint64_t raw_addr = static_cast<uint64_t>(req.addr);
    auto ctrl_empty = [&]() {
      return (m_read_buffer.size() == 0 && m_write_buffer.size() == 0 &&
              m_active_buffer.size() == 0 && m_pending.empty() &&
              m_meta_rd_buffer.size() == 0 && m_meta_wb_buffer.size() == 0);
    };
    if (raw_addr == SENTINEL_DRAIN) {
      return ctrl_empty();
    }
    if (m_rtl_integrity_mode) {
      if (raw_addr == SENTINEL_META_INIT) {
        if (!ctrl_empty()) return false;
        rtl_meta_init();
        return true;
      }
      if (raw_addr == SENTINEL_META_FLUSH) {
        if (!ctrl_empty()) return false;
        rtl_meta_flush();
        return true;
      }
      if (raw_addr == SENTINEL_CACHE_CLEAR) {
        if (!ctrl_empty()) return false;
        rtl_cache_clear();
        return true;
      }
      if ((raw_addr & 0xFF00000000000000ULL) == SENTINEL_FORCE_MINOR_MASK) {
        if (!ctrl_empty()) return false;
        rtl_force_minor(raw_addr & 0xFFFFFFFFULL);
        return true;
      }
      if ((raw_addr & 0xFF00000000000000ULL) == SENTINEL_BMT_FAIL_MASK) {
        if (!ctrl_empty()) return false;
        int fail_lvl = static_cast<int>((raw_addr >> 48) & 0xFULL);
        rtl_bmt_fail(raw_addr & 0xFFFFFFFFULL, fail_lvl);
        return true;
      }
    }

    if (m_integrity_en && (m_meta_rd_buffer.size() >= 64 || m_meta_wb_buffer.size() >= 64)) {
      return false;
    }

    bool ok = false;
    if (m_disable_wr_coalesce) {
      m_addr_mapper->apply(req);
      req.addr_vec[0] = m_channel_id;
      req.final_command = m_device.m_spec->supported_requests[req.type_id];
      req.arrive = m_clk;
      if (req.type_id == Request::Type::Read) {
        ok = m_read_buffer.enqueue(req);
        if (ok) s_num_read_reqs++;
      } else if (req.type_id == Request::Type::Write) {
        ok = m_write_buffer.enqueue(req);
        if (ok) s_num_write_reqs++;
      } else {
        ok = ControllerBase::send(req);
      }
      if (!ok) {
        req.arrive = -1;
        return false;
      }
    } else {
      ok = ControllerBase::send(req);
      if (!ok) {
        return false;
      }
    }

    // Keep m_pending sorted by depart so non-speculative read latency never stalls write-forwarded reads
    if (m_pending.size() >= 2) {
      for (size_t i = m_pending.size() - 1; i > 0; i--) {
        if (m_pending[i].depart < m_pending[i - 1].depart) {
          std::swap(m_pending[i], m_pending[i - 1]);
        } else {
          break;
        }
      }
    }

    if (m_sdc_count_requests && !req.addr_vec.empty()) {
      int flat_bank = m_device.get_flat_bank_id(req.addr_vec);
      int bg_local = (m_bg_level >= 0) ? req.addr_vec[m_bg_level] : 0;
      int bank_local = req.addr_vec[m_bank_level];
      int row = req.addr_vec[m_row_level];
      if (flat_bank >= 0 && flat_bank < m_num_banks) {
        sdc_on_act(flat_bank, bg_local, bank_local, row);
      }
    }

    if (m_integrity_en) {
      if (m_rtl_integrity_mode) {
        handle_integrity_on_user_req_rtl(req);
      } else {
        handle_integrity_on_user_req(req);
      }
    }
    return true;
  }

  void tick() override {
    tick_prologue();

    m_refresh->tick();

    if (m_ref_postpone_max > 0) {
      // Khớp ddr5_cmd_engine.sv:364,986-993: vào ref_mode khi hết traffic hoặc chạm MAX_POSTPONE
      bool ctrl_idle = (m_read_buffer.size() == 0 && m_write_buffer.size() == 0 &&
                        m_active_buffer.size() == 0 && m_meta_rd_buffer.size() == 0 &&
                        m_meta_wb_buffer.size() == 0);
      if (ctrl_idle && !m_deferred_refab_reqs.empty()) {
        m_ref_drain_active = true;
        m_ref_drain_target_owed = 0;
      } else if (!m_ref_drain_active && !m_deferred_refab_reqs.empty() &&
                 m_ref_owed_cnt >= m_ref_postpone_max) {
        m_ref_drain_active = true;
        // Khi rất ít bank mở (<=3, như bank_conflict), đóng bank xong trước khi nạp scrub nên xả hết về 0;
        // khi nhiều bank mở (>3), quá trình đóng bank nạp 1 lệnh giảm thiểu vào s_v nên thoát ref_mode sau 1 REFab
        m_ref_drain_target_owed = (count_open_banks() <= 3) ? 0 : (m_ref_postpone_max - 1);
      }
      if (m_ref_drain_active && !m_refab_dispatched && m_clk >= m_next_ref_allowed_clk) {
        if (!m_deferred_refab_reqs.empty()) {
          Request r = m_deferred_refab_reqs.front();
          if (ControllerBase::priority_send(r)) {
            m_deferred_refab_reqs.pop_front();
            m_refab_dispatched = true;
          }
        } else {
          m_ref_drain_active = false;
        }
      }
    }

    if (m_scrub_interval_ctrl_cycles > 0) {
      int thresh_clk = m_scrub_interval_ctrl_cycles * m_ctrl_ratio;
      if (++m_scrub_timer_clk >= thresh_clk) {
        m_scrub_timer_clk = 0;
        m_scrub_pending = true;
      }
    }

    m_rowpolicy->pre_schedule();
    for (auto* p : m_plugins) {
      p->pre_schedule();
    }

    // SledgeHammer window timer (matches sdc_resilient_filter.sv:361-363)
    m_window_timer++;
    if (m_window_timer >= m_window_size_dram_clk) {
      m_window_timer = 0;
      m_phys_bank_throttled_flags = 0;
      m_coordinated_throttle_active = false;
    }

    // RowPress & tRAS_max monitor on open banks
    check_rowpress_and_tras_max();

    // Expand one aggressor from Alert FIFO into PROQ if capacity allows (directed_refresh_manager.sv:184)
    expand_alert_to_proq();

    bool issued = false;

    // 1. Active buffer (already opened requests awaiting CAS)
    Candidate cand = (m_dq_cas_gap_rd_rd_clk > 0 || m_dq_cas_gap_wr_wr_clk > 0 ||
                      m_dq_cas_gap_rd_wr_clk > 0 || m_dq_cas_gap_wr_rd_clk > 0)
                         ? pick_best_ready_from(m_active_buffer, [&](const Request& r) { return dq_cas_ok(r.command); })
                         : pick_best_ready_from(m_active_buffer, {});
    if (cand.valid) {
      issue_and_advance_candidate(cand, false);
      issued = true;
    }

    // 2. Priority buffer (REFab, RFMab)
    if (!issued) {
      cand = pick_priority_if();
      if (cand.valid) {
        issue_and_advance_candidate(cand, true);
        issued = true;
      }
    }

    // 3. Forced PREpb for tRAS_max clamp or completed victim refresh ACT->tRAS->PREpb
    if (!issued) {
      issued = try_issue_forced_prepb();
    }

    // 4. Hoàn tất đặt chỗ giảm thiểu (PREpb -> ACT), scrub ngay sau REF/RFM, hoặc ưu tiên nạn nhân DRM
    release_stale_mit_reservations();
    bool any_mit_reserved = false;
    for (bool res : m_mit_act_reserved) {
      if (res) {
        any_mit_reserved = true;
        break;
      }
    }
    if (!issued && any_mit_reserved) {
      if (!m_proq.empty()) {
        issued = try_issue_victim_refresh(true);
      }
      int scrub_b = m_scrub_bg * m_num_banks_per_bg + m_scrub_bank;
      if (!issued && m_scrub_pending && scrub_b >= 0 && scrub_b < m_num_banks && m_mit_act_reserved[scrub_b]) {
        issued = try_issue_scrub();
      }
    }
    if (!issued && m_scrub_pending && (m_scrub_armed_by_ref || (m_drm_consec_grants >= 8 && count_open_banks() > 3))) {
      issued = try_issue_scrub();
    }
    if (!issued && !m_proq.empty() &&
        (is_drm_stall() || static_cast<int>(m_proq.size()) >= m_proq_depth / 2 ||
         any_user_blocked_by_proq() || has_ready_second_pair_in_proq())) {
      issued = try_issue_victim_refresh(true);
    }

    // 5. Integrity metadata writebacks (dirty MC eviction)
    if (!issued && m_integrity_en && m_meta_wb_buffer.size() > 0) {
      cand = pick_best_ready_from(m_meta_wb_buffer, [&](const Request& r) { return meta_filter(r); });
      if (cand.valid) {
        issue_and_advance_candidate(cand, false);
        issued = true;
      }
    }

    // 6. Integrity metadata reads (CB / ML / BMT tree nodes)
    if (!issued && m_integrity_en && m_meta_rd_buffer.size() > 0) {
      cand = pick_best_ready_from(m_meta_rd_buffer, [&](const Request& r) { return meta_filter(r); });
      if (cand.valid) {
        issue_and_advance_candidate(cand, false);
        issued = true;
      }
    }

    // 7. User read/write buffer filtered by PROQ blacklist, clamp, and smooth SDC pacing
    if (!issued && m_priority_buffer.size() == 0 && !m_ref_drain_active) {
      cand = pick_rw_if([&](const Request& r) { return user_filter(r); });
      if (cand.valid) {
        issue_and_advance_candidate(cand, false);
        issued = true;
      }
    }

    // 8. Opportunistic / slack-cycle victim refresh or patrol scrubber
    if (!issued && !m_proq.empty()) {
      issued = try_issue_victim_refresh(false);
    }
    if (!issued && m_scrub_pending) {
      int scrub_b = m_scrub_bg * m_num_banks_per_bg + m_scrub_bank;
      bool scrub_b_res = (scrub_b >= 0 && scrub_b < m_num_banks) ? m_mit_act_reserved[scrub_b] : false;
      bool ctrl_slack = (m_active_buffer.size() == 0 && m_read_buffer.size() == 0 && m_write_buffer.size() == 0);
      bool rowhit_slack = (count_open_banks() > 3 && s_rfm_count <= 2 && m_active_buffer.size() == 0 &&
                           (m_clk - m_last_scrub_act_clk) >= static_cast<Clk_t>(1150 * m_ctrl_ratio));
      // Khớp slack_aware_arbiter.sv:189-191: tuần tra ECC khi rảnh thật, ngay sau REF/RFM, hoặc khe rảnh giữa các burst hit
      if (m_scrub_armed_by_ref || (m_drm_consec_grants >= 8 && count_open_banks() > 3) ||
          ctrl_slack || rowhit_slack || scrub_b_res) {
        bool was_rowhit_slack = rowhit_slack && !m_scrub_armed_by_ref;
        issued = try_issue_scrub();
        if (issued && was_rowhit_slack && !m_scrub_pending) {
          m_scrub_timer_clk = 0;
        }
      }
    }

    m_rowpolicy->post_schedule();
    for (auto* p : m_plugins) {
      p->post_schedule();
    }
  }

  void reset_stats() override {
    ControllerBase::reset_stats();
    s_sdc_throttles = 0;
    s_coordinated_throttles = 0;
    s_victim_refreshes = 0;
    s_mit_acts = 0;
    s_traffic_acts = 0;
    s_ref_count = 0;
    s_scrub_acts = 0;
    s_rfm_count = 0;
    s_rowpress_alerts = 0;
    s_tras_clamps = 0;
    s_proq_blocks = 0;
    s_pace_defers = 0;
    s_mc_hits = 0;
    s_mc_misses = 0;
    s_meta_rd_cnt = 0;
    s_meta_wr_cnt = 0;
    s_reencrypt_events = 0;
  }

 private:
  void init_pxor_masks() {
    uint64_t seed_a = m_pxor_seed;
    uint64_t seed_b = (~m_pxor_seed) ^ 0xF0F00F0FAAAA5555ULL;
    if (seed_b == 0ULL) seed_b = 0xA5A55A5A01234567ULL;

    for (int h = 0; h < 8; h++) {
      uint32_t ma = 0;
      uint32_t mb = 0;
      for (int t = 0; t < 22; t++) {
        int idx1 = (t * 3 + h * 7) % 64;
        int idx2 = (t * 5 + h + 13) % 64;
        uint32_t bit_a = ((seed_a >> idx1) ^ (seed_a >> idx2) ^ (t == h ? 1ULL : 0ULL)) & 1ULL;
        uint32_t bit_b = ((seed_b >> idx1) ^ (seed_b >> idx2) ^ (t == h ? 1ULL : 0ULL)) & 1ULL;
        ma |= (bit_a << t);
        mb |= (bit_b << t);
      }
      m_pxor_mask_a[h] = ma;
      m_pxor_mask_b[h] = mb;
    }
  }

  uint32_t make_tag22(int bg_local, int bank_local, int row) const {
    return ((static_cast<uint32_t>(bg_local) & 0x7u) << 19) |
           ((static_cast<uint32_t>(bank_local) & 0x3u) << 17) |
           (static_cast<uint32_t>(row) & 0x1FFFFu);
  }

  uint8_t pxor_eval(uint32_t tag22, const uint32_t masks[8]) const {
    uint8_t out = 0;
    for (int h = 0; h < 8; h++) {
      uint32_t v = tag22 & masks[h];
      if (__builtin_parity(v) & 1) {
        out |= static_cast<uint8_t>(1u << h);
      }
    }
    return out;
  }

  uint8_t xor_fold_eval(uint32_t tag22) const {
    return static_cast<uint8_t>((tag22 & 0xFFu) ^ ((tag22 >> 8) & 0xFFu) ^ ((tag22 >> 16) & 0x3Fu));
  }

  uint8_t crc8_eval(uint32_t tag22) const {
    uint8_t crc = 0xAA;
    for (int i = 21; i >= 0; i--) {
      uint8_t bit = static_cast<uint8_t>((tag22 >> i) & 1u);
      if (((crc >> 7) ^ bit) & 1u) {
        crc = static_cast<uint8_t>((crc << 1) ^ 0x07u);
      } else {
        crc = static_cast<uint8_t>(crc << 1);
      }
    }
    return crc;
  }

  void sdc_on_act(int flat_bank, int bg_local, int bank_local, int row) {
    uint32_t tag22 = make_tag22(bg_local, bank_local, row);
    uint32_t idx_a = (m_pxor_mode ? pxor_eval(tag22, m_pxor_mask_a) : xor_fold_eval(tag22)) %
                     static_cast<uint32_t>(m_table_entries);
    uint32_t idx_b = (m_pxor_mode ? pxor_eval(tag22, m_pxor_mask_b) : crc8_eval(tag22)) %
                     static_cast<uint32_t>(m_table_entries);

    uint16_t cnt_a = (m_table_a_epoch[idx_a] == m_current_epoch) ? m_table_a_cnt[idx_a] : 0;
    uint16_t cnt_b = (m_table_b_epoch[idx_b] == m_current_epoch) ? m_table_b_cnt[idx_b] : 0;

    bool ge_a = (static_cast<int>(cnt_a) >= m_sdc_thresh);
    bool ge_b = (static_cast<int>(cnt_b) >= m_sdc_thresh);
    bool will_throttle = ge_a && (!m_dual_hash_en || ge_b);

    if (will_throttle) {
      // T86 Subtract-T (saturate at 0) instead of hard-resetting to 0
      m_table_a_cnt[idx_a] = ge_a ? static_cast<uint16_t>(cnt_a - m_sdc_thresh) : 0;
      m_table_a_epoch[idx_a] = m_current_epoch;
      if (m_dual_hash_en) {
        m_table_b_cnt[idx_b] = ge_b ? static_cast<uint16_t>(cnt_b - m_sdc_thresh) : 0;
        m_table_b_epoch[idx_b] = m_current_epoch;
      }

      s_sdc_throttles++;
      uint32_t pb = static_cast<uint32_t>((bg_local * m_num_banks_per_bg + bank_local) & 31);
      m_phys_bank_throttled_flags |= (1u << pb);
      if (__builtin_popcount(m_phys_bank_throttled_flags) > m_multibank_thresh) {
        if (!m_coordinated_throttle_active) {
          s_coordinated_throttles++;
        }
        m_coordinated_throttle_active = true;
      }

      Clk_t delay = m_coordinated_throttle_active
                        ? static_cast<Clk_t>(4 * m_throttle_pace_clk)
                        : static_cast<Clk_t>(m_throttle_pace_clk);
      if (delay > 0) {
        m_row_cooldown[flat_bank][row] = m_clk + delay;
      }

      enqueue_aggressor_alert(flat_bank, row);
    } else {
      m_table_a_cnt[idx_a] = (cnt_a < 0xFFFFu) ? static_cast<uint16_t>(cnt_a + 1u) : 0xFFFFu;
      m_table_a_epoch[idx_a] = m_current_epoch;
      if (m_dual_hash_en) {
        m_table_b_cnt[idx_b] = (cnt_b < 0xFFFFu) ? static_cast<uint16_t>(cnt_b + 1u) : 0xFFFFu;
        m_table_b_epoch[idx_b] = m_current_epoch;
      }
    }
  }

  void sdc_on_refab() {
    m_ref_cnt++;
    if (m_ref_cnt >= m_refw_refs) {
      m_ref_cnt = 0;
      m_current_epoch ^= 1u;
    }
  }

  bool is_drm_stall() const {
    int max_victims = 2 * std::clamp(m_blast_radius, 1, 3);
    return (static_cast<int>(m_proq.size()) + max_victims > m_proq_depth) ||
           (m_alert_fifo.size() >= 14);
  }

  void enqueue_aggressor_alert(int flat_bank, int row, bool from_rowpress = false) {
    if (flat_bank < 0 || flat_bank >= m_num_banks || row < 0 || row >= m_num_rows) {
      return;
    }
    AggressorAlert a;
    a.bank = flat_bank;
    a.row = row;
    a.from_rowpress = from_rowpress;
    a.addr_vec = m_bank_addr_templates[flat_bank];
    a.addr_vec[m_row_level] = row;
    m_alert_fifo.push_back(std::move(a));
  }

  void expand_alert_to_proq() {
    if (m_alert_fifo.empty()) return;
    int max_victims = 2 * std::clamp(m_blast_radius, 1, 3);
    if (static_cast<int>(m_proq.size()) + max_victims > m_proq_depth) {
      return;
    }
    AggressorAlert a = std::move(m_alert_fifo.front());
    m_alert_fifo.pop_front();

    std::vector<int> offsets;
    offsets.push_back(1);
    offsets.push_back(-1);
    if (m_blast_radius >= 2) {
      offsets.push_back(2);
      offsets.push_back(-2);
    }
    if (m_blast_radius >= 3) {
      offsets.push_back(3);
      offsets.push_back(-3);
    }

    for (int d : offsets) {
      int v = a.row + d;
      if (v < 0 || v >= m_num_rows) continue;
      bool dup = false;
      for (const auto& pe : m_proq) {
        if (pe.bank == a.bank && pe.row == v) {
          dup = true;
          break;
        }
      }
      if (!dup) {
        ProqEntry p;
        p.bank = a.bank;
        p.row = v;
        p.from_rowpress = a.from_rowpress;
        p.addr_vec = a.addr_vec;
        p.addr_vec[m_row_level] = v;
        m_proq.push_back(std::move(p));
      }
    }
  }

  int calc_dyn_rowpress_thresh(int base_th, int curve, int duration) const {
    int th = base_th;
    switch (curve) {
      case 0:
        th = base_th;
        break;
      case 1:
        if (duration > 4000) th = base_th >> 2;
        else if (duration > 2000) th = base_th >> 1;
        else if (duration > 1000) th = base_th - (base_th >> 2);
        break;
      case 2:
        if (duration > 3000) th = base_th >> 3;
        else if (duration > 1500) th = base_th >> 2;
        else if (duration > 800) th = base_th >> 1;
        else if (duration > 400) th = base_th - (base_th >> 2);
        break;
      case 3:
        if (duration > 2000) th = 128;
        else if (duration > 1000) th = base_th >> 3;
        else if (duration > 500) th = base_th >> 2;
        else if (duration > 200) th = base_th >> 1;
        break;
      default:
        th = base_th;
        break;
    }
    if (base_th < 64) return th;
    return std::max(64, th);
  }

  void check_rowpress_and_tras_max() {
    for (int b = 0; b < m_num_banks; b++) {
      if (m_bank_open_row[b] < 0) continue;
      int dur_ctrl = static_cast<int>((m_clk - m_bank_open_clk[b]) / m_ctrl_ratio);

      if (m_rp_base_ctrl_cyc > 0 && !m_rp_alerted[b]) {
        int dyn = calc_dyn_rowpress_thresh(m_rp_base_ctrl_cyc, m_rowpress_curve, dur_ctrl);
        if (dur_ctrl >= dyn) {
          m_rp_alerted[b] = true;
          s_rowpress_alerts++;
          enqueue_aggressor_alert(b, m_bank_open_row[b], true);
        }
      }

      if (m_tras_max_ctrl_cyc > 0 && !m_tras_clamp_pending[b] && dur_ctrl >= m_tras_max_ctrl_cyc) {
        m_tras_clamp_pending[b] = true;
        s_tras_clamps++;
        enqueue_aggressor_alert(b, m_bank_open_row[b], true);
      }
    }
  }

  bool is_proq_blacklisted(int flat_bank, int row) const {
    for (const auto& pe : m_proq) {
      if (pe.bank == flat_bank && (pe.row == row || pe.row == row + 1 || pe.row == row - 1)) {
        return true;
      }
    }
    for (const auto& a : m_alert_fifo) {
      if (a.bank == flat_bank && a.row == row) {
        return true;
      }
    }
    return false;
  }

  bool any_user_blocked_by_proq() const {
    for (const auto& r : m_read_buffer.buffer) {
      if (!r.addr_vec.empty()) {
        int b = m_device.get_flat_bank_id(r.addr_vec);
        int row = r.addr_vec[m_row_level];
        if (is_proq_blacklisted(b, row)) return true;
      }
    }
    for (const auto& r : m_write_buffer.buffer) {
      if (!r.addr_vec.empty()) {
        int b = m_device.get_flat_bank_id(r.addr_vec);
        int row = r.addr_vec[m_row_level];
        if (is_proq_blacklisted(b, row)) return true;
      }
    }
    if (m_integrity_en && !m_meta_bypass_drm) {
      for (const auto& r : m_meta_rd_buffer.buffer) {
        if (!r.addr_vec.empty()) {
          int b = m_device.get_flat_bank_id(r.addr_vec);
          int row = r.addr_vec[m_row_level];
          if (is_proq_blacklisted(b, row)) return true;
        }
      }
      for (const auto& r : m_meta_wb_buffer.buffer) {
        if (!r.addr_vec.empty()) {
          int b = m_device.get_flat_bank_id(r.addr_vec);
          int row = r.addr_vec[m_row_level];
          if (is_proq_blacklisted(b, row)) return true;
        }
      }
    }
    return false;
  }

  bool is_rd_cas(int cmd) const {
    return (cmd == m_cmd_rd) || (m_cmd_rda >= 0 && cmd == m_cmd_rda);
  }

  bool is_wr_cas(int cmd) const {
    return (cmd == m_cmd_wr) || (m_cmd_wra >= 0 && cmd == m_cmd_wra);
  }

  bool dq_cas_ok(int cmd) const {
    if (is_rd_cas(cmd) && m_clk < m_next_rd_cas_clk) return false;
    if (is_wr_cas(cmd) && m_clk < m_next_wr_cas_clk) return false;
    return true;
  }

  bool meta_filter(const Request& req) {
    if (!dq_cas_ok(req.command)) return false;
    if (would_close_active(req)) return false;
    if (!req.addr_vec.empty()) {
      int b = m_device.get_flat_bank_id(req.addr_vec);
      if (b >= 0 && b < m_num_banks) {
        if (m_tras_clamp_pending[b] || m_victim_close_req[b] || m_mit_act_reserved[b]) {
          return false;
        }
        // Khớp RTL (axi_ddr5_mc_secure_top -> u_mc_core -> u_sdc_filter -> u_drm): metadata chịu đủ stall/blacklist/pacing
        if (!m_meta_bypass_drm) {
          if (is_drm_stall() && req.command == m_cmd_act) {
            s_proq_blocks++;
            return false;
          }
          int row = req.addr_vec[m_row_level];
          if (is_proq_blacklisted(b, row)) {
            s_proq_blocks++;
            return false;
          }
          if (req.command == m_cmd_act) {
            auto it = m_row_cooldown[b].find(row);
            if (it != m_row_cooldown[b].end()) {
              if (m_clk < it->second) {
                s_pace_defers++;
                return false;
              }
              m_row_cooldown[b].erase(it);
            }
          }
        }
      }
    }
    return true;
  }

  bool user_filter(const Request& req) {
    if (!dq_cas_ok(req.command)) return false;
    if (req.addr_vec.empty()) return true;
    int b = m_device.get_flat_bank_id(req.addr_vec);
    if (b < 0 || b >= m_num_banks) return true;
    if (m_tras_clamp_pending[b] || m_victim_close_req[b] || m_mit_act_reserved[b]) {
      return false;
    }
    if (is_drm_stall() && req.command == m_cmd_act) {
      s_proq_blocks++;
      return false;
    }
    int row = req.addr_vec[m_row_level];
    if (is_proq_blacklisted(b, row)) {
      s_proq_blocks++;
      return false;
    }
    if (req.command == m_cmd_act) {
      auto it = m_row_cooldown[b].find(row);
      if (it != m_row_cooldown[b].end()) {
        if (m_clk < it->second) {
          s_pace_defers++;
          return false;
        }
        m_row_cooldown[b].erase(it);
      }
    }
    return true;
  }

  void issue_cmd_and_notify(const Request& req, bool is_mitigation) {
    m_device.issue_command(req.command, req.addr_vec, m_clk);
    m_rowpolicy->on_issue(req);
    for (auto* p : m_plugins) {
      p->on_issue(req);
    }

    const auto* spec = m_device.m_spec;
    const int cmd = req.command;

    if (spec->command_meta[cmd].is_opening &&
        spec->bank_targets[cmd] == BankTarget::Single &&
        !req.addr_vec.empty()) {
      int flat_bank = m_device.get_flat_bank_id(req.addr_vec);
      int row = req.addr_vec[m_row_level];
      int rank = (m_rank_level >= 0) ? req.addr_vec[m_rank_level] : 0;
      int bg_local = (m_bg_level >= 0) ? req.addr_vec[m_bg_level] : 0;
      int bank_local = req.addr_vec[m_bank_level];

      if (flat_bank >= 0 && flat_bank < m_num_banks) {
        m_bank_open_row[flat_bank] = row;
        m_bank_open_clk[flat_bank] = m_clk;
        m_rp_alerted[flat_bank] = false;
        m_tras_clamp_pending[flat_bank] = false;
      }

      if (!is_mitigation && req.type_id != -1) {
        s_traffic_acts++;
      }

      if (!is_mitigation && !m_sdc_count_requests && flat_bank >= 0 && flat_bank < m_num_banks) {
        sdc_on_act(flat_bank, bg_local, bank_local, row);
      }

      if (m_raammt_thresh > 0 && m_cmd_rfmab >= 0 && rank >= 0 && rank < m_num_ranks &&
          bg_local >= 0 && bg_local < m_num_bgs_per_rank) {
        m_rolling_act_cnt[rank][bg_local]++;
        if (m_rolling_act_cnt[rank][bg_local] >= m_raammt_thresh && !m_rfm_pending[rank]) {
          AddrVec_t rfm_addr(spec->level_count, -1);
          rfm_addr[0] = m_channel_id;
          if (m_rank_level >= 0) rfm_addr[m_rank_level] = rank;
          Request rfm_req(std::move(rfm_addr), Request::Cmd, m_cmd_rfmab);
          if (priority_send(rfm_req)) {
            m_rfm_pending[rank] = true;
          }
        }
      }
      return;
    }

    if (is_rd_cas(cmd)) {
      if (m_dq_cas_gap_rd_rd_clk > 0) m_next_rd_cas_clk = std::max(m_next_rd_cas_clk, m_clk + m_dq_cas_gap_rd_rd_clk);
      if (m_dq_cas_gap_rd_wr_clk > 0) m_next_wr_cas_clk = std::max(m_next_wr_cas_clk, m_clk + m_dq_cas_gap_rd_wr_clk);
    } else if (is_wr_cas(cmd)) {
      if (m_dq_cas_gap_wr_wr_clk > 0) m_next_wr_cas_clk = std::max(m_next_wr_cas_clk, m_clk + m_dq_cas_gap_wr_wr_clk);
      if (m_dq_cas_gap_wr_rd_clk > 0) m_next_rd_cas_clk = std::max(m_next_rd_cas_clk, m_clk + m_dq_cas_gap_wr_rd_clk);
    }

    if (spec->command_meta[cmd].is_closing) {
      m_device.for_each_target_bank(cmd, req.addr_vec, [&](int bank_id) {
        if (bank_id >= 0 && bank_id < m_num_banks) {
          m_bank_open_row[bank_id] = -1;
          m_bank_open_clk[bank_id] = 0;
          m_rp_alerted[bank_id] = false;
          m_tras_clamp_pending[bank_id] = false;
          m_victim_close_req[bank_id] = false;
        }
      });
    }

    if (cmd == m_cmd_refab) {
      s_ref_count++;
      m_next_ref_allowed_clk = m_clk + static_cast<Clk_t>(118 * m_ctrl_ratio);
      std::fill(m_mit_act_reserved.begin(), m_mit_act_reserved.end(), false);
      if (m_scrub_pending) {
        m_scrub_armed_by_ref = true;
      }
      if (m_ref_postpone_max > 0) {
        m_ref_owed_cnt = std::max(0, m_ref_owed_cnt - 1);
        m_refab_dispatched = false;
        if (m_deferred_refab_reqs.empty() || m_ref_owed_cnt <= m_ref_drain_target_owed) {
          m_ref_drain_active = false;
        }
      }
      sdc_on_refab();
    } else if (cmd == m_cmd_rfmab) {
      int rank = (m_rank_level >= 0 && !req.addr_vec.empty() && req.addr_vec[m_rank_level] >= 0)
                     ? req.addr_vec[m_rank_level]
                     : 0;
      if (rank >= 0 && rank < m_num_ranks) {
        std::fill(m_rolling_act_cnt[rank].begin(), m_rolling_act_cnt[rank].end(), 0);
        m_rfm_pending[rank] = false;
      }
      m_next_ref_allowed_clk = m_clk + static_cast<Clk_t>(118 * m_ctrl_ratio);
      std::fill(m_mit_act_reserved.begin(), m_mit_act_reserved.end(), false);
      if (m_scrub_pending && count_banks_with_queued_rowhit() <= 1) {
        m_scrub_armed_by_ref = true;
      }
      s_rfm_count++;
    }
  }

  void retire_request_qshield(ReqBuffer::iterator& req_it, ReqBuffer& buffer) {
    int extra_rd_clk = (m_integrity_en && m_crypto_extra_lat_clk > 0)
                           ? (m_crypto_extra_lat_clk + m_rtl_rd_extra_lat_clk)
                           : m_rtl_rd_extra_lat_clk;
    if (req_it->type_id == Request::Type::Read && extra_rd_clk > 0) {
      if (&buffer == &m_active_buffer) {
        m_active_per_bank[m_device.get_flat_bank_id(req_it->addr_vec)]--;
      }
      Request completed = *req_it;
      completed.depart = m_clk + m_device.m_spec->read_latency + extra_rd_clk;
      auto pos = std::upper_bound(m_pending.begin(), m_pending.end(), completed.depart,
                                  [](Clk_t val, const Request& r) { return val < r.depart; });
      m_pending.insert(pos, completed);
      s_num_read_reqs_served++;
      buffer.remove(req_it);
      return;
    }

    retire_request(req_it, buffer);
    // Keep m_pending sorted in case ControllerBase::retire_request pushed behind a higher depart time
    if (m_pending.size() >= 2) {
      for (size_t i = m_pending.size() - 1; i > 0; i--) {
        if (m_pending[i].depart < m_pending[i - 1].depart) {
          std::swap(m_pending[i], m_pending[i - 1]);
        } else {
          break;
        }
      }
    }
  }

  void issue_and_advance_candidate(Candidate& cand, bool is_priority) {
    if (cand.it->type_id != -1) {
      m_rowpolicy->try_upgrade_command(*cand.it);
    }
    if (!cand.it->is_stat_updated && cand.it->type_id != -1) {
      update_request_stats(cand.it);
    }

    issue_cmd_and_notify(*cand.it, false);

    if (cand.it->command == cand.it->final_command) {
      retire_request_qshield(cand.it, *cand.buffer);
    } else if (m_device.m_spec->command_meta[cand.it->command].is_opening) {
      promote_to_active(cand.it, *cand.buffer);
    }
    (void)is_priority;
  }

  bool try_issue_forced_prepb() {
    for (int b = 0; b < m_num_banks; b++) {
      if (!(m_tras_clamp_pending[b] || m_victim_close_req[b])) continue;
      if (m_active_per_bank[b] > 0) continue;
      if (m_bank_open_row[b] < 0) {
        m_tras_clamp_pending[b] = false;
        m_victim_close_req[b] = false;
        continue;
      }
      if (!check_timing(m_cmd_prepb, m_bank_addr_templates[b])) continue;

      Request pre_req(m_bank_addr_templates[b], Request::Cmd, m_cmd_prepb);
      pre_req.command = m_cmd_prepb;
      issue_cmd_and_notify(pre_req, true);
      return true;
    }
    return false;
  }

  int count_open_banks() const {
    int cnt = 0;
    for (int b = 0; b < m_num_banks; b++) {
      if (m_bank_open_row[b] >= 0) cnt++;
    }
    return cnt;
  }

  bool has_proq_for_bank(int b) const {
    for (const auto& pe : m_proq) {
      if (pe.bank == b) return true;
    }
    return false;
  }

  int count_proq_for_bank(int b) const {
    int cnt = 0;
    for (const auto& pe : m_proq) {
      if (pe.bank == b) cnt++;
    }
    return cnt;
  }

  bool bank_has_queued_user_req(int b) const {
    for (const auto& r : m_read_buffer.buffer) {
      if (!r.addr_vec.empty() && m_device.get_flat_bank_id(r.addr_vec) == b) return true;
    }
    for (const auto& r : m_write_buffer.buffer) {
      if (!r.addr_vec.empty() && m_device.get_flat_bank_id(r.addr_vec) == b) return true;
    }
    return false;
  }

  bool bank_has_queued_rowhit(int b) const {
    if (b < 0 || b >= m_num_banks || m_bank_open_row[b] < 0) return false;
    int open_r = m_bank_open_row[b];
    for (const auto& r : m_read_buffer.buffer) {
      if (!r.addr_vec.empty() && m_device.get_flat_bank_id(r.addr_vec) == b && r.addr_vec[m_row_level] == open_r) {
        return true;
      }
    }
    for (const auto& r : m_write_buffer.buffer) {
      if (!r.addr_vec.empty() && m_device.get_flat_bank_id(r.addr_vec) == b && r.addr_vec[m_row_level] == open_r) {
        return true;
      }
    }
    return false;
  }

  int count_banks_with_queued_rowhit() const {
    int cnt = 0;
    for (int b = 0; b < m_num_banks; b++) {
      if (bank_has_queued_rowhit(b)) cnt++;
    }
    return cnt;
  }

  bool has_ready_second_pair_in_proq() const {
    for (const auto& pe : m_proq) {
      int b = pe.bank;
      if (b >= 0 && b < m_num_banks && !pe.from_rowpress && m_bank_open_row[b] >= 0 &&
          (m_clk - m_bank_open_clk[b]) >= static_cast<Clk_t>(7 * m_ctrl_ratio)) {
        return true;
      }
    }
    return false;
  }

  bool keep_reservation_after_proq_pop(int b, bool was_from_rowpress) const {
    int rem = count_proq_for_bank(b);
    if (rem <= 0) return false;
    if (was_from_rowpress) return true;
    if (rem == 2 && bank_has_queued_user_req(b)) {
      // Sau cặp {+1,-1} của SDC throttle, nhường 1 lượt mở hàng cho user trước khi làm tươi cặp {+2,-2}
      return false;
    }
    return true;
  }

  void release_stale_mit_reservations() {
    int scrub_b = m_scrub_pending ? (m_scrub_bg * m_num_banks_per_bg + m_scrub_bank) : -1;
    for (int b = 0; b < m_num_banks; b++) {
      if (!m_mit_act_reserved[b]) continue;
      bool needed = (b == scrub_b) || has_proq_for_bank(b);
      if (!needed) {
        m_mit_act_reserved[b] = false;
      }
    }
  }

  bool try_issue_victim_refresh(bool allow_preempt_open = true) {
    for (auto it = m_proq.begin(); it != m_proq.end();) {
      int b = it->bank;
      if (b < 0 || b >= m_num_banks) {
        it = m_proq.erase(it);
        continue;
      }
      if (m_active_per_bank[b] > 0 || m_victim_close_req[b] || m_tras_clamp_pending[b]) {
        ++it;
        continue;
      }
      if (m_bank_open_row[b] == it->row) {
        // Victim row is already open in the bank, so it is refreshed now
        bool was_rp = it->from_rowpress;
        s_victim_refreshes++;
        m_drm_consec_grants = std::min(15, m_drm_consec_grants + 1);
        m_proq.erase(it);
        m_mit_act_reserved[b] = keep_reservation_after_proq_pop(b, was_rp);
        return false;
      }
      if (m_bank_open_row[b] >= 0) {
        if (!allow_preempt_open && !m_mit_act_reserved[b] && bank_has_queued_rowhit(b)) {
          ++it;
          continue;
        }
        if (check_timing(m_cmd_prepb, m_bank_addr_templates[b])) {
          Request pre_req(m_bank_addr_templates[b], Request::Cmd, m_cmd_prepb);
          pre_req.command = m_cmd_prepb;
          m_mit_act_reserved[b] = true;
          issue_cmd_and_notify(pre_req, true);
          return true;
        }
        ++it;
        continue;
      }
      // Bank closed: avoid delaying pending priority REFab/RFMab with new victim ACT
      if (m_priority_buffer.size() > 0 || m_ref_drain_active) {
        ++it;
        continue;
      }
      if (check_timing(m_cmd_act, it->addr_vec)) {
        bool was_rp = it->from_rowpress;
        Request act_req(it->addr_vec, Request::Cmd, m_cmd_act);
        act_req.command = m_cmd_act;
        act_req.source_id = -99;
        m_victim_close_req[b] = true;
        issue_cmd_and_notify(act_req, true);
        s_victim_refreshes++;
        s_mit_acts++;
        m_drm_consec_grants = std::min(15, m_drm_consec_grants + 1);
        m_proq.erase(it);
        m_mit_act_reserved[b] = keep_reservation_after_proq_pop(b, was_rp);
        return true;
      }
      ++it;
    }
    return false;
  }

  void advance_scrub_coords() {
    m_scrub_pending = false;
    m_scrub_armed_by_ref = false;
    m_drm_consec_grants = 0;
    m_scrub_bg++;
    if (m_scrub_bg >= m_num_bgs_per_rank) {
      m_scrub_bg = 0;
      m_scrub_bank++;
      if (m_scrub_bank >= m_num_banks_per_bg) {
        m_scrub_bank = 0;
        m_scrub_row = (m_scrub_row + 1) % std::max(1, m_num_rows);
      }
    }
  }

  // Tuần tra ECC nền (ecc_scrubber.sv + directed_refresh_manager.sv:527-565)
  bool try_issue_scrub() {
    if (!m_scrub_pending) return false;
    int b = m_scrub_bg * m_num_banks_per_bg + m_scrub_bank;
    if (b < 0 || b >= m_num_banks) {
      advance_scrub_coords();
      return false;
    }
    if (m_active_per_bank[b] > 0 || m_victim_close_req[b] || m_tras_clamp_pending[b] ||
        (m_mit_act_reserved[b] && has_proq_for_bank(b))) {
      return false;
    }
    if (m_bank_open_row[b] == m_scrub_row) {
      m_mit_act_reserved[b] = false;
      m_last_scrub_act_clk = m_clk;
      advance_scrub_coords();
      return false;
    }
    if (m_bank_open_row[b] >= 0) {
      if (check_timing(m_cmd_prepb, m_bank_addr_templates[b])) {
        Request pre_req(m_bank_addr_templates[b], Request::Cmd, m_cmd_prepb);
        pre_req.command = m_cmd_prepb;
        m_mit_act_reserved[b] = true;
        issue_cmd_and_notify(pre_req, true);
        return true;
      }
      return false;
    }
    if (m_priority_buffer.size() > 0 || m_ref_drain_active) {
      return false;
    }
    AddrVec_t act_vec = m_bank_addr_templates[b];
    act_vec[m_row_level] = m_scrub_row;
    if (check_timing(m_cmd_act, act_vec)) {
      Request act_req(act_vec, Request::Cmd, m_cmd_act);
      act_req.command = m_cmd_act;
      act_req.source_id = -99;
      m_mit_act_reserved[b] = false;
      m_victim_close_req[b] = true;
      issue_cmd_and_notify(act_req, true);
      s_mit_acts++;
      s_scrub_acts++;
      m_last_scrub_act_clk = m_clk;
      advance_scrub_coords();
      return true;
    }
    return false;
  }

  // 3-bit Tree-PLRU (exact match to rtl/crypto/qshield_meta_cache.sv:87-99)
  static uint8_t next_plru(uint8_t cur, int w) {
    uint8_t b0 = (cur >> 2) & 1u;
    uint8_t b1 = (cur >> 1) & 1u;
    uint8_t b2 = cur & 1u;
    switch (w) {
      case 0: b0 = 1; b1 = 1; break;
      case 1: b0 = 1; b1 = 0; break;
      case 2: b0 = 0; b2 = 1; break;
      case 3: b0 = 0; b2 = 0; break;
      default: break;
    }
    return static_cast<uint8_t>((b0 << 2) | (b1 << 1) | b2);
  }

  static int pick_plru_victim(uint8_t cur) {
    uint8_t b0 = (cur >> 2) & 1u;
    uint8_t b1 = (cur >> 1) & 1u;
    uint8_t b2 = cur & 1u;
    if (b0 == 0) {
      return (b1 == 0) ? 0 : 1;
    }
    return (b2 == 0) ? 2 : 3;
  }

  uint64_t tn_addr(int level, uint64_t idx) const {
    if (level < 1 || level > static_cast<int>(m_tn_offsets.size())) return m_tn_base;
    return m_tn_base + ((m_tn_offsets[level - 1] + idx) << 6);
  }

  void enqueue_meta_dram_req(uint64_t meta_addr, bool is_write) {
    Request mr(static_cast<Addr_t>(meta_addr), is_write ? Request::Type::Write : Request::Type::Read);
    mr.intra_channel_addr = static_cast<Addr_t>(meta_addr % m_channel_cap_bytes);
    mr.size_bytes = 64;
    m_addr_mapper->apply(mr);
    mr.addr_vec[0] = m_channel_id;
    mr.final_command = m_device.m_spec->supported_requests[is_write ? Request::Type::Write : Request::Type::Read];
    mr.type_id = -1;  // Internal metadata traffic: uses real DRAM timing/bandwidth without distorting user stats
    mr.source_id = -77;
    mr.arrive = m_clk;

    if (is_write) {
      if (m_meta_wb_buffer.enqueue(mr)) {
        s_meta_wr_cnt++;
      }
    } else {
      if (m_meta_rd_buffer.enqueue(mr)) {
        s_meta_rd_cnt++;
      }
    }
  }

  bool mc_lookup_and_touch(uint64_t addr, bool make_dirty) {
    uint64_t set_idx = (addr >> 6) % static_cast<uint64_t>(m_mc_sets);
    McSet& s = m_mc[set_idx];
    for (int w = 0; w < m_mc_ways; w++) {
      if (s.ways[w].valid && s.ways[w].addr == addr) {
        s_mc_hits++;
        if (make_dirty) s.ways[w].dirty = true;
        s.plru = next_plru(s.plru, w);
        return true;
      }
    }
    s_mc_misses++;
    return false;
  }

  void mc_fill(uint64_t addr, uint8_t level, uint64_t idx, bool dirty, int depth) {
    uint64_t set_idx = (addr >> 6) % static_cast<uint64_t>(m_mc_sets);
    McSet& s = m_mc[set_idx];

    for (int w = 0; w < m_mc_ways; w++) {
      if (s.ways[w].valid && s.ways[w].addr == addr) {
        if (dirty) s.ways[w].dirty = true;
        s.plru = next_plru(s.plru, w);
        return;
      }
    }

    int target_w = -1;
    for (int w = 0; w < m_mc_ways; w++) {
      if (!s.ways[w].valid) {
        target_w = w;
        break;
      }
    }
    if (target_w < 0) {
      target_w = pick_plru_victim(s.plru);
      McLine evicted = s.ways[target_w];
      if (evicted.valid && evicted.dirty) {
        enqueue_meta_dram_req(evicted.addr, true);
        // Lazy BMT propagation up to parent node on dirty CB/TN eviction
        if (depth < 4 && evicted.level < static_cast<uint8_t>(m_tree_levels)) {
          uint8_t p_lvl = evicted.level + 1;
          uint64_t p_idx = evicted.idx >> 3;
          uint64_t p_addr = tn_addr(p_lvl, p_idx);
          if (!mc_lookup_and_touch(p_addr, true)) {
            enqueue_meta_dram_req(p_addr, false);
            mc_fill(p_addr, p_lvl, p_idx, true, depth + 1);
          }
        }
      }
    }

    s.ways[target_w] = McLine{true, dirty, addr, level, idx};
    s.plru = next_plru(s.plru, target_w);
  }

  void handle_integrity_on_user_req(const Request& req) {
    uint64_t line_idx = (static_cast<uint64_t>(req.addr) >> 6) & static_cast<uint64_t>(m_prot_lines - 1);
    uint64_t cb_idx = line_idx >> 6;
    uint64_t ml_idx = line_idx >> 3;
    uint64_t cb_addr = m_meta_base + (cb_idx << 6);
    uint64_t ml_addr = m_ml_base + (ml_idx << 6);
    bool is_write = (req.type_id == Request::Type::Write);

    // 1. Counter Block lookup + BMT verification walk up to first cached level or root
    if (!mc_lookup_and_touch(cb_addr, is_write)) {
      enqueue_meta_dram_req(cb_addr, false);
      for (int lvl = 1; lvl <= m_tree_levels; lvl++) {
        uint64_t n_idx = cb_idx >> (3 * lvl);
        uint64_t n_addr = tn_addr(lvl, n_idx);
        if (mc_lookup_and_touch(n_addr, false)) {
          break;
        }
        enqueue_meta_dram_req(n_addr, false);
        mc_fill(n_addr, static_cast<uint8_t>(lvl), n_idx, false, 0);
      }
      mc_fill(cb_addr, 0, cb_idx, is_write, 0);
    }

    // 2. MAC Line lookup (no BMT walk needed; MAC binds counter verified above)
    if (!mc_lookup_and_touch(ml_addr, is_write)) {
      enqueue_meta_dram_req(ml_addr, false);
      mc_fill(ml_addr, 5, ml_idx, is_write, 0);
    }

    // 3. Minor counter increment & 127->0 rollover re-encryption of 63 sibling lines
    if (is_write) {
      uint8_t& minor = m_minor_cnt[line_idx];
      if (minor >= 127) {
        minor = 0;
        s_reencrypt_events++;
        uint64_t sib_base = (cb_idx << 6);
        for (uint64_t k = 0; k < 64; k++) {
          uint64_t sib_line = sib_base + k;
          if (sib_line == line_idx) continue;
          if (m_meta_rd_buffer.size() + 2 <= m_meta_rd_buffer.max_size &&
              m_meta_wb_buffer.size() + 2 <= m_meta_wb_buffer.max_size) {
            enqueue_meta_dram_req(sib_line << 6, false);
            enqueue_meta_dram_req(sib_line << 6, true);
          }
        }
      } else {
        minor++;
      }
    }
  }

  // ---- Chế độ toàn vẹn khớp từng giao dịch với RTL (qshield_bmt_engine + qshield_axi_crypto_bridge) ----
  bool mc_find_silent(uint64_t addr, bool make_dirty) {
    uint64_t set_idx = (addr >> 6) % static_cast<uint64_t>(m_mc_sets);
    McSet& s = m_mc[set_idx];
    for (int w = 0; w < m_mc_ways; w++) {
      if (s.ways[w].valid && s.ways[w].addr == addr) {
        if (make_dirty) s.ways[w].dirty = true;
        s.plru = next_plru(s.plru, w);
        return true;
      }
    }
    return false;
  }

  void mc_evict_propagate_silent(const McLine& evicted, int depth) {
    enqueue_meta_dram_req(evicted.addr, true);
    if (depth < 4 && evicted.level < static_cast<uint8_t>(m_tree_levels)) {
      uint8_t p_lvl = evicted.level + 1;
      uint64_t p_idx = evicted.idx >> 3;
      uint64_t p_addr = tn_addr(p_lvl, p_idx);
      if (!mc_find_silent(p_addr, true)) {
        enqueue_meta_dram_req(p_addr, false);
        mc_fill_silent(p_addr, p_lvl, p_idx, true, depth + 1);
      }
    }
  }

  void mc_fill_silent(uint64_t addr, uint8_t level, uint64_t idx, bool dirty, int depth) {
    uint64_t set_idx = (addr >> 6) % static_cast<uint64_t>(m_mc_sets);
    McSet& s = m_mc[set_idx];
    for (int w = 0; w < m_mc_ways; w++) {
      if (s.ways[w].valid && s.ways[w].addr == addr) {
        if (dirty) s.ways[w].dirty = true;
        s.plru = next_plru(s.plru, w);
        return;
      }
    }
    int target_w = -1;
    for (int w = 0; w < m_mc_ways; w++) {
      if (!s.ways[w].valid) {
        target_w = w;
        break;
      }
    }
    if (target_w < 0) {
      target_w = pick_plru_victim(s.plru);
      McLine evicted = s.ways[target_w];
      // Điền đường mới trước khi lan truyền node cha nếu cần đẩy tuần tự
      s.ways[target_w] = McLine{true, dirty, addr, level, idx};
      s.plru = next_plru(s.plru, target_w);
      if (evicted.valid && evicted.dirty) {
        mc_evict_propagate_silent(evicted, depth);
      }
      return;
    }
    s.ways[target_w] = McLine{true, dirty, addr, level, idx};
    s.plru = next_plru(s.plru, target_w);
  }

  bool rtl_bmt_verify(uint64_t line_idx) {
    uint64_t cb_idx = line_idx >> 6;
    uint64_t cb_addr = m_meta_base + (cb_idx << 6);
    if (mc_find_silent(cb_addr, false)) {
      s_mc_hits++;
      return true;
    }

    // Trượt CB: đi ngược lên cây cho tới khi gặp node đã nằm trong MC hoặc gốc trên chip
    struct NodeStep {
      uint64_t addr;
      uint8_t level;
      uint64_t idx;
    };
    std::vector<NodeStep> missed;
    missed.push_back({cb_addr, 0, cb_idx});
    enqueue_meta_dram_req(cb_addr, false);

    for (int lvl = 1; lvl <= m_tree_levels; lvl++) {
      uint64_t n_idx = cb_idx >> (3 * lvl);
      uint64_t n_addr = tn_addr(lvl, n_idx);
      if (mc_find_silent(n_addr, false)) {
        break;
      }
      enqueue_meta_dram_req(n_addr, false);
      missed.push_back({n_addr, static_cast<uint8_t>(lvl), n_idx});
    }
    // Nạp từ mức cao nhất xuống CB khớp qshield_bmt_engine.sv:888-920
    for (int i = static_cast<int>(missed.size()) - 1; i >= 0; i--) {
      mc_fill_silent(missed[i].addr, missed[i].level, missed[i].idx, false, 0);
    }
    s_mc_misses++;
    return true;
  }

  void rtl_bmt_update(uint64_t line_idx) {
    uint64_t cb_idx = line_idx >> 6;
    uint64_t cb_addr = m_meta_base + (cb_idx << 6);
    if (!mc_find_silent(cb_addr, true)) {
      mc_fill_silent(cb_addr, 0, cb_idx, true, 0);
    }
    s_mc_hits++;
  }

  void rtl_ml_access(uint64_t line_idx, bool is_write) {
    uint64_t ml_idx = line_idx >> 3;
    uint64_t ml_addr = m_ml_base + (ml_idx << 6);
    uint64_t set_idx = ml_idx & 0x3ULL;
    MlSet& ms = m_ml_cache[set_idx];
    for (int w = 0; w < 2; w++) {
      if (ms.ways[w].valid && ms.ways[w].idx == ml_idx) {
        s_mc_hits++;
        if (is_write) ms.ways[w].dirty = true;
        ms.plru = static_cast<uint8_t>(1 - w);
        return;
      }
    }
    int v = !ms.ways[0].valid ? 0 : (!ms.ways[1].valid ? 1 : static_cast<int>(ms.plru & 1u));
    if (ms.ways[v].valid && ms.ways[v].dirty) {
      enqueue_meta_dram_req(ms.ways[v].addr, true);
      if (m_rtl_ml_reenc_ack_overlap) {
        // Phản ánh trễ xóa 1 chu kỳ ml_dram_wr_ack trong qshield_axi_crypto_bridge.sv:644-647,885
        enqueue_meta_dram_req(ms.ways[v].addr, true);
      }
      if (ms.ways[v].idx < m_ml_dram_inited.size()) {
        m_ml_dram_inited[ms.ways[v].idx] = true;
      }
      ms.ways[v].dirty = false;
    }
    bool inited = (ml_idx < m_ml_dram_inited.size()) ? m_ml_dram_inited[ml_idx] : false;
    if (inited) {
      s_mc_misses++;
      enqueue_meta_dram_req(ml_addr, false);
      if (m_rtl_ml_reenc_ack_overlap) {
        enqueue_meta_dram_req(ml_addr, false);
      }
    }
    ms.ways[v] = MlLine{true, is_write, ml_idx, ml_addr};
    ms.plru = static_cast<uint8_t>(1 - v);
  }

  void rtl_meta_init() {
    uint64_t num_cb = static_cast<uint64_t>(m_prot_lines) / 64ULL;
    for (uint64_t i = 0; i < num_cb; i++) {
      enqueue_meta_dram_req(m_meta_base + (i << 6), true);
    }
    uint64_t lvl_cnt = num_cb / 8ULL;
    for (int lvl = 1; lvl <= m_tree_levels && lvl_cnt > 0; lvl++) {
      for (uint64_t i = 0; i < lvl_cnt; i++) {
        enqueue_meta_dram_req(tn_addr(lvl, i), true);
      }
      lvl_cnt /= 8ULL;
    }
    rtl_cache_clear();
    std::fill(m_ml_dram_inited.begin(), m_ml_dram_inited.end(), false);
    m_minor_cnt.clear();
  }

  void rtl_meta_flush() {
    for (int pass = 0; pass <= m_tree_levels; pass++) {
      bool any_flushed = false;
      for (int s = 0; s < m_mc_sets; s++) {
        for (int w = 0; w < m_mc_ways; w++) {
          McLine& line = m_mc[s].ways[w];
          if (line.valid && line.dirty) {
            line.dirty = false;
            any_flushed = true;
            McLine copy = line;
            mc_evict_propagate_silent(copy, 0);
          }
        }
      }
      if (!any_flushed) break;
    }
    for (int s = 0; s < 4; s++) {
      for (int w = 0; w < 2; w++) {
        MlLine& line = m_ml_cache[s].ways[w];
        if (line.valid && line.dirty) {
          enqueue_meta_dram_req(line.addr, true);
          if (m_rtl_ml_reenc_ack_overlap) {
            enqueue_meta_dram_req(line.addr, true);
          }
          if (line.idx < m_ml_dram_inited.size()) {
            m_ml_dram_inited[line.idx] = true;
          }
          line.dirty = false;
        }
      }
    }
  }

  void rtl_cache_clear() {
    for (auto& s : m_mc) {
      for (auto& w : s.ways) {
        w.valid = false;
        w.dirty = false;
      }
    }
    for (auto& ms : m_ml_cache) {
      for (int w = 0; w < 2; w++) {
        ms.ways[w].valid = false;
        ms.ways[w].dirty = false;
      }
    }
  }

  void rtl_force_minor(uint64_t addr) {
    uint64_t line_idx = (addr >> 6) & static_cast<uint64_t>(m_prot_lines - 1);
    rtl_bmt_verify(line_idx);
    rtl_bmt_update(line_idx);
    m_minor_cnt[line_idx] = 127;
  }

  void rtl_bmt_fail(uint64_t addr, int fail_lvl) {
    uint64_t line_idx = (addr >> 6) & static_cast<uint64_t>(m_prot_lines - 1);
    uint64_t cb_idx = line_idx >> 6;
    uint64_t cb_addr = m_meta_base + (cb_idx << 6);
    int max_lvl = std::clamp(fail_lvl, 0, m_tree_levels);
    if (!mc_find_silent(cb_addr, false)) {
      enqueue_meta_dram_req(cb_addr, false);
      for (int lvl = 1; lvl <= max_lvl; lvl++) {
        uint64_t n_idx = cb_idx >> (3 * lvl);
        uint64_t n_addr = tn_addr(lvl, n_idx);
        if (mc_find_silent(n_addr, false)) {
          break;
        }
        enqueue_meta_dram_req(n_addr, false);
      }
      s_mc_misses++;
    } else {
      s_mc_hits++;
    }
  }

  void handle_integrity_on_user_req_rtl(const Request& req) {
    uint64_t line_idx = (static_cast<uint64_t>(req.addr) >> 6) & static_cast<uint64_t>(m_prot_lines - 1);
    uint64_t cb_idx = line_idx >> 6;
    bool is_write = (req.type_id == Request::Type::Write);

    if (is_write) {
      rtl_bmt_verify(line_idx);
      uint8_t& minor = m_minor_cnt[line_idx];
      if (minor >= 127) {
        minor = 0;
        s_reencrypt_events++;
        rtl_bmt_update(line_idx);
        rtl_ml_access(line_idx, true);

        // Quét lại 63 dòng anh em trong cùng CB: chỉ tái mã hóa các khe có minor > 0
        uint64_t sib_base = cb_idx << 6;
        for (uint64_t k = 0; k < 64; k++) {
          uint64_t sib_line = sib_base + k;
          if (sib_line == line_idx) continue;
          auto it = m_minor_cnt.find(sib_line);
          if (it != m_minor_cnt.end() && it->second > 0) {
            enqueue_meta_dram_req(sib_line << 6, false);
            if (m_rtl_ml_reenc_ack_overlap) {
              // Phản ánh trễ xóa 1 chu kỳ reenc_dram_rd_valid_in/wr_ack trong qshield_axi_crypto_bridge.sv:651,753,2575
              enqueue_meta_dram_req(sib_line << 6, false);
            }
            rtl_ml_access(sib_line, false);
            rtl_ml_access(sib_line, true);
            enqueue_meta_dram_req(sib_line << 6, true);
            if (m_rtl_ml_reenc_ack_overlap) {
              enqueue_meta_dram_req(sib_line << 6, true);
            }
            it->second = 0;
          }
        }
      } else {
        minor++;
        rtl_bmt_update(line_idx);
        rtl_ml_access(line_idx, true);
      }
    } else {
      rtl_bmt_verify(line_idx);
      rtl_ml_access(line_idx, false);
    }
  }
};

}  // namespace Ramulator
