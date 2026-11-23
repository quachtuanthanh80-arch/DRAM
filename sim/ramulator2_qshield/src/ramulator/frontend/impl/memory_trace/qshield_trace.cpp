// File: sim/ramulator2_qshield/src/ramulator/frontend/impl/memory_trace/qshield_trace.cpp
// Chức năng: Frontend phát trace 64B theo nhịp AXI RTL, hỗ trợ giới hạn ROB/WriteQueue đang bay và lệnh đồng bộ T38.

#include <cstdint>
#include <filesystem>
#include <fmt/format.h>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "ramulator/base/param.h"
#include "ramulator/frontend/i_frontend.h"

namespace Ramulator {

namespace fs = std::filesystem;

class QShieldTrace : public IFrontEnd, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IFrontEnd, QShieldTrace, "QShieldTrace")

 private:
  enum class OpKind { Read, Write, Ctrl };
  struct TraceOp {
    OpKind kind = OpKind::Read;
    Addr_t addr = 0;
  };

  // Mã sentinel 64-bit dương dùng để đồng bộ xả ống và tái hiện kịch bản T38
  static constexpr uint64_t SENTINEL_DRAIN = 0x7000000000000000ULL;
  static constexpr uint64_t SENTINEL_META_INIT = 0x7000000000000001ULL;
  static constexpr uint64_t SENTINEL_META_FLUSH = 0x7000000000000002ULL;
  static constexpr uint64_t SENTINEL_CACHE_CLEAR = 0x7000000000000003ULL;
  static constexpr uint64_t SENTINEL_FORCE_MINOR_MASK = 0x7100000000000000ULL;
  static constexpr uint64_t SENTINEL_BMT_FAIL_MASK = 0x7200000000000000ULL;

  std::string m_trace_path;
  int m_max_outstanding_reads = 0;
  int m_max_outstanding_writes = 0;
  int m_issue_gap_fe_ticks = 1;
  bool m_sequential_ops = false;
  bool m_drain_controller = true;

  std::vector<TraceOp> m_trace;
  size_t m_curr_idx = 0;
  Clk_t m_last_issue_clk = -1000;
  int m_inflight_reads = 0;
  int m_inflight_writes = 0;
  bool m_drain_done = false;

  size_t s_reads_issued = 0;
  size_t s_writes_issued = 0;
  size_t s_reads_done = 0;
  size_t s_writes_done = 0;
  size_t s_total_rd_lat_fe_ticks = 0;
  double s_avg_rd_lat_fe_ticks = 0.0;
  size_t s_fe_ticks = 0;

 public:
  void init() override {
    RAMULATOR_PARSE_PARAM(m_clock_ratio, unsigned int, "clock_ratio").required();
    RAMULATOR_PARSE_PARAM(m_trace_path, std::string, "path").required();
    RAMULATOR_PARSE_PARAM(m_max_outstanding_reads, int, "max_outstanding_reads").default_val(0);
    RAMULATOR_PARSE_PARAM(m_max_outstanding_writes, int, "max_outstanding_writes").default_val(0);
    RAMULATOR_PARSE_PARAM(m_issue_gap_fe_ticks, int, "issue_gap_fe_ticks").default_val(1);
    RAMULATOR_PARSE_PARAM(m_sequential_ops, bool, "sequential_ops").default_val(false);
    RAMULATOR_PARSE_PARAM(m_drain_controller, bool, "drain_controller").default_val(true);

    if (m_issue_gap_fe_ticks < 1) {
      m_issue_gap_fe_ticks = 1;
    }
    init_trace(m_trace_path);
  }

  void setup(IFrontEnd* frontend, IMemorySystem* memory_system) override {
    m_stats.add("qshield_trace_fe_ticks", s_fe_ticks);
    m_stats.add("qshield_trace_reads_issued", s_reads_issued);
    m_stats.add("qshield_trace_writes_issued", s_writes_issued);
    m_stats.add("qshield_trace_reads_done", s_reads_done);
    m_stats.add("qshield_trace_writes_done", s_writes_done);
    m_stats.add("qshield_trace_total_rd_lat_fe_ticks", s_total_rd_lat_fe_ticks);
    m_stats.add("qshield_trace_avg_rd_lat_fe_ticks", s_avg_rd_lat_fe_ticks);
  }

  void tick() override {
    m_clk++;
    s_fe_ticks = static_cast<size_t>(m_clk);

    if (m_curr_idx >= m_trace.size()) {
      if (m_inflight_reads == 0 && m_inflight_writes == 0 && !m_drain_done) {
        if (!m_drain_controller) {
          m_drain_done = true;
        } else {
          Request drain_req(static_cast<Addr_t>(SENTINEL_DRAIN), Request::Type::Read);
          drain_req.size_bytes = m_memory_system->get_tx_bytes();
          if (m_memory_system->send(drain_req)) {
            m_drain_done = true;
          }
        }
      }
      return;
    }

    if ((m_clk - m_last_issue_clk) < m_issue_gap_fe_ticks) {
      return;
    }

    const TraceOp& op = m_trace[m_curr_idx];
    if (op.kind == OpKind::Ctrl) {
      // Lệnh điều khiển (META_INIT / META_FLUSH / CACHE_CLEAR / FORCE_MINOR / LD_BMT_FAIL) chờ rỗng ống trước khi chạy
      if (m_inflight_reads > 0 || m_inflight_writes > 0) {
        return;
      }
      Request req(op.addr, Request::Type::Read);
      req.size_bytes = m_memory_system->get_tx_bytes();
      if (m_memory_system->send(req)) {
        m_last_issue_clk = m_clk;
        m_curr_idx++;
      }
      return;
    }

    if (m_sequential_ops && (m_inflight_reads > 0 || m_inflight_writes > 0)) {
      return;
    }
    if (op.kind == OpKind::Read && m_max_outstanding_reads > 0 && m_inflight_reads >= m_max_outstanding_reads) {
      return;
    }
    if (op.kind == OpKind::Write && m_max_outstanding_writes > 0 && m_inflight_writes >= m_max_outstanding_writes) {
      return;
    }

    const Clk_t issue_clk = m_clk;
    int req_type = (op.kind == OpKind::Write) ? Request::Type::Write : Request::Type::Read;
    Request req(op.addr, req_type, 0, [this, op_kind = op.kind, issue_clk](Request&) {
      if (op_kind == OpKind::Read) {
        m_inflight_reads--;
        s_reads_done++;
        if (m_clk >= issue_clk) {
          s_total_rd_lat_fe_ticks += static_cast<size_t>(m_clk - issue_clk);
        }
      } else {
        m_inflight_writes--;
        s_writes_done++;
      }
    });
    req.size_bytes = m_memory_system->get_tx_bytes();

    if (m_memory_system->send(req)) {
      if (op.kind == OpKind::Read) {
        m_inflight_reads++;
        s_reads_issued++;
      } else {
        m_inflight_writes++;
        s_writes_issued++;
      }
      m_last_issue_clk = m_clk;
      m_curr_idx++;
    }
  }

  bool is_finished() override {
    return (m_curr_idx >= m_trace.size()) && (m_inflight_reads == 0) && (m_inflight_writes == 0) && m_drain_done;
  }

  void update_stats() override {
    s_fe_ticks = static_cast<size_t>(m_clk);
    s_avg_rd_lat_fe_ticks = (s_reads_done > 0)
                                ? (static_cast<double>(s_total_rd_lat_fe_ticks) / static_cast<double>(s_reads_done))
                                : 0.0;
  }

  void finalize() override { update_stats(); }

 private:
  static Addr_t parse_hex_addr(const std::string& tok) {
    std::string s = tok;
    if (s.rfind("0x", 0) == 0 || s.rfind("0X", 0) == 0) {
      s = s.substr(2);
    }
    return static_cast<Addr_t>(std::stoull(s, nullptr, 16));
  }

  void init_trace(const std::string& file_path_str) {
    fs::path trace_path(file_path_str);
    if (!fs::exists(trace_path)) {
      throw std::runtime_error(fmt::format("QShieldTrace: trace '{}' does not exist", file_path_str));
    }
    std::ifstream in(trace_path);
    if (!in.is_open()) {
      throw std::runtime_error(fmt::format("QShieldTrace: cannot open '{}'", file_path_str));
    }

    std::string line;
    int line_num = 0;
    while (std::getline(in, line)) {
      line_num++;
      if (!line.empty() && line.back() == '\r') {
        line.pop_back();
      }
      std::vector<std::string> tokens;
      std::istringstream iss(line);
      std::string tok;
      while (iss >> tok) {
        tokens.push_back(tok);
      }
      if (tokens.empty() || tokens[0][0] == '#') {
        continue;
      }

      if (tokens[0] == "LD" && tokens.size() >= 2) {
        m_trace.push_back({OpKind::Read, parse_hex_addr(tokens[1])});
      } else if (tokens[0] == "ST" && tokens.size() >= 2) {
        m_trace.push_back({OpKind::Write, parse_hex_addr(tokens[1])});
      } else if (tokens[0] == "META_INIT") {
        m_trace.push_back({OpKind::Ctrl, static_cast<Addr_t>(SENTINEL_META_INIT)});
      } else if (tokens[0] == "META_FLUSH") {
        m_trace.push_back({OpKind::Ctrl, static_cast<Addr_t>(SENTINEL_META_FLUSH)});
      } else if (tokens[0] == "CACHE_CLEAR") {
        m_trace.push_back({OpKind::Ctrl, static_cast<Addr_t>(SENTINEL_CACHE_CLEAR)});
      } else if (tokens[0] == "FORCE_MINOR" && tokens.size() >= 2) {
        uint64_t a = static_cast<uint64_t>(parse_hex_addr(tokens[1])) & 0xFFFFFFFFULL;
        m_trace.push_back({OpKind::Ctrl, static_cast<Addr_t>(SENTINEL_FORCE_MINOR_MASK | a)});
      } else if (tokens[0] == "LD_BMT_FAIL" && tokens.size() >= 3) {
        uint64_t a = static_cast<uint64_t>(parse_hex_addr(tokens[1])) & 0xFFFFFFFFULL;
        uint64_t lvl = static_cast<uint64_t>(std::stoi(tokens[2])) & 0xFULL;
        m_trace.push_back({OpKind::Ctrl, static_cast<Addr_t>(SENTINEL_BMT_FAIL_MASK | (lvl << 48) | a)});
      } else {
        throw std::runtime_error(fmt::format("QShieldTrace: {} line {}: invalid token '{}'", file_path_str, line_num, tokens[0]));
      }
    }
  }
};

}  // namespace Ramulator
