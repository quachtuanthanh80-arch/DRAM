// File: sim/ramulator2_qshield/src/ramulator/controller/addr_mapper/impl/qshield_addr_mapper.cpp
// Chức năng: Bộ ánh xạ địa chỉ khớp RTL (domain_bank_coloring + SCARF Feistel 10 vòng) cho Ramulator2.

#include <algorithm>
#include <cstdint>
#include <string>

#include "ramulator/controller/addr_mapper/addr_mapper_base.h"
#include "ramulator/controller/addr_mapper/i_addr_mapper.h"
#include "ramulator/dram/dram_spec.h"

namespace Ramulator {

class QShieldAddrMapper : public IAddrMapper, public AddrMapperBase {
  RAMULATOR_REGISTER_IMPLEMENTATION_DERIVED(IAddrMapper, QShieldAddrMapper, AddrMapperBase, "QShieldAddrMapper")

 private:
  bool m_scramble_en = false;
  std::string m_scramble_seed_hex = "13579BDF2468ACE0";
  bool m_is_ddr5 = true;
  uint64_t m_seed = 0x13579BDF2468ACE0ULL;

  int m_rank_level = -1;
  int m_bg_level = -1;
  int m_bank_level = -1;
  int m_row_level = -1;
  int m_col_level = -1;

  int m_num_bgs = 8;
  int m_num_banks = 4;
  int m_num_rows = 131072;
  int m_num_cols = 128;

  static uint32_t scarf_sbox(uint32_t x) {
    static constexpr uint32_t SBOX[16] = {
        0xCu, 0x5u, 0x6u, 0xBu, 0x9u, 0x0u, 0xAu, 0xDu,
        0x3u, 0xEu, 0xFu, 0x8u, 0x4u, 0x7u, 0x1u, 0x2u};
    return SBOX[x & 0xFu];
  }

  // Nửa vòng F (nhánh 10-bit -> 9-bit) khớp rtl/core/scarf_dram_randomizer.sv:60-81
  static uint32_t feistel_f(uint32_t r_in, uint32_t rkey, uint32_t twk) {
    uint32_t mixed = (r_in ^ (twk & 0x3FFu) ^ (((rkey & 0xFFu) << 2) | (rkey & 0x3u))) & 0x3FFu;
    uint32_t s0 = scarf_sbox(mixed & 0xFu);
    uint32_t s1 = scarf_sbox((mixed >> 4) & 0xFu);
    uint32_t s_hi = ((mixed >> 8) & 0x3u) ^ (s0 & 0x3u);
    uint32_t subbed = (s_hi << 8) | (s1 << 4) | s0;
    uint32_t rot_a = ((subbed & 0xFFu) << 1) | ((subbed >> 9) & 0x1u);
    uint32_t rot_b = ((subbed & 0xFu) << 5) | ((subbed >> 4) & 0x1Fu);
    return (rot_a ^ rot_b) & 0x1FFu;
  }

  // Nửa vòng G (nhánh 9-bit -> 10-bit) khớp rtl/core/scarf_dram_randomizer.sv:84-97
  static uint32_t feistel_g(uint32_t l_in, uint32_t rkey, uint32_t twk) {
    uint32_t l_ext = ((l_in & 0x1u) << 9) | (l_in & 0x1FFu);
    uint32_t rk_ext = ((rkey & 0x3u) << 8) | (rkey & 0xFFu);
    uint32_t mixed = (l_ext ^ (twk & 0x3FFu) ^ rk_ext) & 0x3FFu;
    uint32_t s0 = scarf_sbox(mixed & 0xFu);
    uint32_t s1 = scarf_sbox((mixed >> 4) & 0xFu);
    uint32_t s_hi = ((mixed >> 8) & 0x3u) ^ (((s1 >> 1) & 0x1u) << 1) ^ ((s0 >> 2) & 0x1u);
    uint32_t subbed = (s_hi << 8) | (s1 << 4) | s0;
    uint32_t rot_a = ((subbed & 0x7Fu) << 3) | ((subbed >> 7) & 0x7u);
    uint32_t rot_b = ((subbed & 0x1Fu) << 5) | ((subbed >> 5) & 0x1Fu);
    return (rot_a ^ rot_b) & 0x3FFu;
  }

 public:
  void init() override {
    AddrMapperBase::init();
    RAMULATOR_PARSE_PARAM(m_scramble_en, bool, "scramble_en").default_val(false);
    RAMULATOR_PARSE_PARAM(m_scramble_seed_hex, std::string, "scramble_seed_hex").default_val("13579BDF2468ACE0");
    RAMULATOR_PARSE_PARAM(m_is_ddr5, bool, "is_ddr5").default_val(true);

    m_seed = std::stoull(m_scramble_seed_hex, nullptr, 16);

    const auto* spec = m_ctrl->m_device.m_spec;
    m_rank_level = spec->has_level("Rank") ? spec->get_level_id("Rank") : -1;
    m_bg_level = spec->has_level("BankGroup") ? spec->get_level_id("BankGroup") : -1;
    m_bank_level = spec->get_level_id("Bank");
    m_row_level = spec->get_level_id("Row");
    m_col_level = spec->get_level_id("Column");

    m_num_bgs = (m_bg_level >= 0) ? spec->get_level_size("BankGroup") : 1;
    m_num_banks = spec->get_level_size("Bank");
    m_num_rows = spec->get_level_size("Row");
    int col_bits = (m_col_idx >= 0 && m_col_idx < static_cast<int>(m_addr_bits.size())) ? m_addr_bits[m_col_idx] : 7;
    m_num_cols = std::max(1, 1 << col_bits);
  }

  void apply(Request& req) override {
    req.addr_vec.resize(m_num_mapped_levels + 1, -1);

    uint64_t a = static_cast<uint64_t>(req.intra_channel_addr);
    // Giải mã chuẩn domain_bank_coloring.sv:28,36 và addr_mapper_ddr5.sv:70,91-92
    uint32_t bg = m_is_ddr5 ? static_cast<uint32_t>(((a >> 6) & 0x7u) ^ ((a >> 18) & 0x7u))
                            : static_cast<uint32_t>(((a >> 6) & 0x3u) ^ ((a >> 18) & 0x3u));
    uint32_t bank = static_cast<uint32_t>((a >> 16) & 0x3u);
    uint32_t row = static_cast<uint32_t>((a >> 18) & 0x3FFFu);
    uint32_t col = static_cast<uint32_t>((a >> m_tx_offset) & static_cast<uint64_t>(m_num_cols - 1));

    // Hoán vị 10 vòng Feistel không cân bằng 9/10-bit lên {bank[1:0], row[16:0]} với tweak = BG
    if (m_scramble_en) {
      uint32_t raw_input = ((bank & 0x3u) << 17) | (row & 0x1FFFFu);
      uint32_t l = raw_input & 0x1FFu;
      uint32_t r_hi = (raw_input >> 9) & 0x3FFu;
      uint32_t twk = bg & 0x3FFu;
      for (int rnd = 0; rnd < 10; rnd++) {
        uint32_t rkey = (static_cast<uint32_t>(m_seed >> ((rnd * 6) % 56)) ^ static_cast<uint32_t>(rnd)) & 0xFFu;
        if ((rnd % 2) == 0) {
          l = (l ^ feistel_f(r_hi, rkey, twk)) & 0x1FFu;
        } else {
          r_hi = (r_hi ^ feistel_g(l, rkey, twk)) & 0x3FFu;
        }
      }
      uint32_t scrambled_full = ((r_hi & 0x3FFu) << 9) | (l & 0x1FFu);
      bank = (scrambled_full >> 17) & 0x3u;
      row = scrambled_full & 0x1FFFFu;
    }

    if (m_rank_level >= 0) req.addr_vec[m_rank_level] = 0;
    if (m_bg_level >= 0) req.addr_vec[m_bg_level] = static_cast<int>(bg % static_cast<uint32_t>(m_num_bgs));
    if (m_bank_level >= 0) req.addr_vec[m_bank_level] = static_cast<int>(bank % static_cast<uint32_t>(m_num_banks));
    if (m_row_level >= 0) req.addr_vec[m_row_level] = static_cast<int>(row % static_cast<uint32_t>(m_num_rows));
    if (m_col_level >= 0) req.addr_vec[m_col_level] = static_cast<int>(col % static_cast<uint32_t>(m_num_cols));
  }
};

}  // namespace Ramulator
