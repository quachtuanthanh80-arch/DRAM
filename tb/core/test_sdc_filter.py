#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5 Memory Controller
# Testbench:   test_sdc_filter.py
# Description: Verifies Novelty Pillar #1 (Configurable Dual-Hash SDC Filter):
#              1. RowHammer activation threshold detection & throttle flag assertion.
#              2. Dual-Hash false-positive collision suppression.
#              3. O(1) epoch reset tied to tREFW (8192 REFab) via epoch tagging.
#=============================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.cfg_hash_mode.value = 1  # Dual-Hash default
    dut.cfg_sdc_thresh.value = 5  # Alert after 5 activations
    dut.cfg_window_size.value = 1000  # Large window for normal test
    dut.cfg_pxor_mode.value = 0
    dut.cfg_pxor_seed.value = 0xA5A5_5A5A_0123_4567
    dut.cfg_multibank_thresh.value = 2
    dut.i_rowpress_weight.value = 0
    dut.i_ref_tick.value = 0

    dut.i_cmd_valid.value = 0
    dut.i_cmd_id.value = 0
    dut.i_cmd_is_write.value = 0
    dut.i_cmd_bg.value = 0
    dut.i_cmd_bank.value = 0
    dut.i_cmd_row.value = 0
    dut.i_cmd_col.value = 0
    dut.i_cmd_len.value = 0
    dut.i_cmd_qos.value = 0
    dut.i_cmd_ready.value = 1

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_rowhammer_threshold_detection(dut):
    """Verify repeated activations of aggressor row trigger throttle & mitigation alert"""
    clock = Clock(dut.clk, 2.5, unit="ns")  # 400 MHz
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.cfg_sdc_thresh.value = 4  # Alert on 4th activation

    aggressor_row = 0x01A5B
    aggressor_bg = 2
    aggressor_bank = 1

    throttled_observed = False
    out_idx = 0

    for access in range(8):
        if access < 6:
            dut.i_cmd_valid.value = 1
            dut.i_cmd_id.value = access
            dut.i_cmd_bg.value = aggressor_bg
            dut.i_cmd_bank.value = aggressor_bank
            dut.i_cmd_row.value = aggressor_row
        else:
            dut.i_cmd_valid.value = 0

        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

        if int(dut.o_cmd_valid.value) == 1:
            is_throttled = int(dut.o_cmd_throttled.value)
            mit_req = int(dut.o_mitigation_req.value)
            alert = int(dut.o_sdc_alert.value)

            dut._log.info(f"Access {out_idx+1}: Throttled={is_throttled}, MitigationReq={mit_req}, Alert={alert}")

            # Pipeline 3 tầng (p1 -> p2 -> out): access thứ T+1 bị throttle và phát giảm thiểu; sau đó đếm lại từ 0
            if out_idx == 4:
                assert is_throttled == 1 and mit_req == 1, f"Expected access {out_idx+1} to be throttled with mitigation!"
                throttled_observed = True
            else:
                assert is_throttled == 0, f"Access {out_idx+1} must not be throttled (count restarts after mitigation)"
            out_idx += 1

    dut.i_cmd_valid.value = 0
    await RisingEdge(dut.clk)

    assert out_idx == 6, f"Expected 6 valid pipelined outputs, got {out_idx}"
    assert throttled_observed, "Attacker row was never throttled!"
    assert int(dut.o_telemetry_throttles.value) > 0, "Telemetry throttle count must be > 0"
    dut._log.info("RowHammer threshold detection and throttle flag verified successfully!")

@cocotb.test()
async def test_epoch_reset_tied_to_trefw(dut):
    """Counts survive any split shorter than tREFW (8192 REFab) and reset in O(1) once a full tREFW has elapsed"""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    dut.i_ref_tick.value = 0
    thresh = 3
    dut.cfg_sdc_thresh.value = thresh
    refw = int(dut.REFW_REFS.value)

    async def access(row):
        dut.i_cmd_valid.value = 1
        dut.i_cmd_row.value = row
        await RisingEdge(dut.clk)
        dut.i_cmd_valid.value = 0
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        assert int(dut.o_cmd_valid.value) == 1, "Expected o_cmd_valid after 3-stage pipeline"
        return int(dut.o_cmd_throttled.value)

    async def ref_ticks(n):
        for _ in range(n):
            dut.i_ref_tick.value = 1
            await RisingEdge(dut.clk)
        dut.i_ref_tick.value = 0
        await RisingEdge(dut.clk)

    # Cross-epoch split (S8): T ACT, then refw-1 REF (less than one tREFW), then one more ACT -> must still be throttled
    row_a = 0x0CDEF
    for _ in range(thresh):
        assert await access(row_a) == 0
    await ref_ticks(refw - 1)
    assert await access(row_a) == 1, "Count was dropped before a full tREFW elapsed (split hammering escapes)"

    # Full tREFW: T ACT, then the remaining REFs to complete the epoch -> counter reset, next ACT not throttled
    row_b = 0x01234
    for _ in range(thresh):
        assert await access(row_b) == 0
    await ref_ticks(1)
    assert await access(row_b) == 0, "Row must start a fresh count after a full tREFW"
    dut._log.info(f"Epoch reset tied to tREFW ({refw} REFab) verified")

#=============================================================================
# Golden Reference Model (HPCA '24 CoMeT / HPCA '21 BlockHammer inspired)
#=============================================================================
class CountMinSketchGoldenModel:
    """Cycle-accurate Software Golden Model of the Dual-Hash Count-Min Sketch filter."""

    def __init__(self, table_entries=256, count_width=16, threshold=4, window_size=50):
        self.table_entries = table_entries
        self.count_width = count_width
        self.threshold = threshold
        self.window_size = window_size
        self.max_count = (1 << count_width) - 1

        self.table_a = [0] * table_entries
        self.table_a_epoch = [0] * table_entries
        self.table_b = [0] * table_entries
        self.table_b_epoch = [0] * table_entries

        self.window_timer = 0
        self.current_epoch = 0

    def calc_hash_a(self, bg, bank, row):
        tag = (bg << (2 + 17)) | (bank << 17) | row
        b0 = tag & 0xFF
        b1 = (tag >> 8) & 0xFF
        b2 = (tag >> 16) & 0x3F
        return (b0 ^ b1 ^ b2) & 0xFF

    def calc_hash_b(self, bg, bank, row):
        tag = (bg << (2 + 17)) | (bank << 17) | row
        crc = 0xAA
        for i in range(21, -1, -1):
            bit = (tag >> i) & 1
            if ((crc >> 7) ^ bit) == 1:
                crc = ((crc << 1) & 0xFF) ^ 0x07
            else:
                crc = (crc << 1) & 0xFF
        return crc & 0xFF

    def step_window_timer(self):
        # Epoch chỉ đổi theo REFab (tREFW); traffic thuần không làm đổi epoch
        pass

    def evaluate_and_update(self, bg, bank, row, valid):
        if not valid:
            self.step_window_timer()
            return 0, False

        ha = self.calc_hash_a(bg, bank, row)
        hb = self.calc_hash_b(bg, bank, row)

        cnt_a = self.table_a[ha] if self.table_a_epoch[ha] == self.current_epoch else 0
        cnt_b = self.table_b[hb] if self.table_b_epoch[hb] == self.current_epoch else 0

        effective_count = min(cnt_a, cnt_b)
        will_throttle = (effective_count >= self.threshold)

        # Update tables on handshake: reaching the threshold triggers mitigation and restarts the row's count
        self.table_a[ha] = 0 if will_throttle else min(cnt_a + 1, self.max_count)
        self.table_a_epoch[ha] = self.current_epoch
        self.table_b[hb] = 0 if will_throttle else min(cnt_b + 1, self.max_count)
        self.table_b_epoch[hb] = self.current_epoch

        self.step_window_timer()
        return effective_count, will_throttle

@cocotb.test()
async def test_sdc_filter_comet_golden_model_cross_verification(dut):
    """Cross-verifies RTL dual-hash filter cycle-by-cycle against CoMeT Golden Model."""
    clock = Clock(dut.clk, 2.5, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    threshold = 4
    window_size = 60
    dut.cfg_sdc_thresh.value = threshold
    dut.cfg_window_size.value = window_size
    dut.cfg_hash_mode.value = 1  # Dual-hash
    dut.cfg_multibank_thresh.value = 7  # Disable multi-bank lock for pure sketch equivalence

    golden = CountMinSketchGoldenModel(threshold=threshold, window_size=window_size)

    # Generate pseudo-random mixed workload: 40 benign accesses + targeted RowHammer bursts
    traffic_pattern = [
        # (bg, bank, row, is_valid)
        (0, 0, 0x00100, True),
        (0, 1, 0x00200, True),
        (1, 0, 0x00300, True),
        (0, 0, 0x00100, True),
        (2, 2, 0x00400, True),
        # Target aggressor row repeated accesses
        (3, 1, 0x05A5A, True),
        (3, 1, 0x05A5A, True),
        (3, 1, 0x05A5A, True),
        (3, 1, 0x05A5A, True),  # 4th access -> should trigger throttling!
        (3, 1, 0x05A5A, True),  # 5th access -> throttled
        (0, 0, 0x00100, True),  # benign access
        (3, 1, 0x05A5A, True),  # aggressor again
    ]

    # Add random accesses
    for i in range(25):
        bg = (i * 3 + 1) % 8
        bank = (i * 2) % 4
        row = (i * 1337 + 0x10) & 0x1FFFF
        traffic_pattern.append((bg, bank, row, True))

    dut._log.info(f"Starting Golden Model Cross-Verification with {len(traffic_pattern)} transactions...")

    pipe_q = []
    for step, (bg, bank, row, valid) in enumerate(traffic_pattern + [(0, 0, 0, False), (0, 0, 0, False)]):
        if valid:
            exp_count, exp_throttle = golden.evaluate_and_update(bg, bank, row, valid)
            pipe_q.append((step, bg, bank, row, exp_count, exp_throttle))

            dut.i_cmd_valid.value = 1
            dut.i_cmd_id.value = step & 0xF
            dut.i_cmd_bg.value = bg
            dut.i_cmd_bank.value = bank
            dut.i_cmd_row.value = row
            dut.i_cmd_col.value = 0x10
            dut.i_cmd_len.value = 0
        else:
            dut.i_cmd_valid.value = 0

        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

        # Kiểm tra đầu ra sau pipeline 3 tầng khớp dự đoán của mô hình vàng
        if int(dut.o_cmd_valid.value) == 1:
            s_step, s_bg, s_bank, s_row, exp_count, exp_throttle = pipe_q.pop(0)
            dut_throttled = int(dut.o_cmd_throttled.value)
            assert dut_throttled == int(exp_throttle), (
                f"Step {s_step} Mismatch: bg={s_bg}, bank={s_bank}, row={hex(s_row)}: "
                f"DUT throttled={dut_throttled}, Expected={int(exp_throttle)} (Golden count={exp_count})"
            )

    assert len(pipe_q) == 0, f"Unflushed pipeline items: {len(pipe_q)}"
    dut.i_cmd_valid.value = 0
    await RisingEdge(dut.clk)
    dut._log.info("CoMeT Golden Model Cross-Verification PASSED with 100% equivalence!")

