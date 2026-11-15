#!/usr/bin/env python3
"""Công cụ tiêm lỗi đột biến RTL (RTL Mutation Testing Engine) cho dự án Q-Shield.

Thực hiện theo brief T62 và quy tắc R-05:
Đảo điều kiện, đổi toán tử, bỏ nhánh tại 4 khối cốt lõi:
  1. scheduler (rtl/backend/ddr5_cmd_engine.sv)
  2. rob (rtl/core/reorder_buffer_rob.sv)
  3. adapter (rtl/frontend/axi_burst_splitter.sv)
  4. csr (rtl/bus/apb_csr_regs.sv)

Báo tỉ lệ mutant bị bắt (killed), mutant sống sót (survived) và nêu rõ phạm vi lựa chọn.
Đảm bảo luôn hoàn nguyên RTL về trạng thái ban đầu sau mỗi lần thử nghiệm.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Cấu hình danh sách 20 đột biến xác định (5 mutant / khối x 4 khối)
MUTANTS = [
    # -------------------------------------------------------------------------
    # 1. SCHEDULER (rtl/backend/ddr5_cmd_engine.sv) - Test: tb_ddr5_cmd_engine
    # -------------------------------------------------------------------------
    {
        "id": "MUT-SCHED-01",
        "block": "scheduler",
        "file": "rtl/backend/ddr5_cmd_engine.sv",
        "description": "Đảo điều kiện kiểm tra nợ refresh (ref_owed != '0 -> ref_owed == '0)",
        "target": "assign refresh_needed = ((ref_owed != '0) && ((s_v == '0) || ref_owed >= 3'(MAX_POSTPONE))) || (|rfm_req) || abo_rfm_req;",
        "mutation": "assign refresh_needed = ((ref_owed == '0) && ((s_v == '0) || ref_owed >= 3'(MAX_POSTPONE))) || (|rfm_req) || abo_rfm_req;",
        "test": "tb_ddr5_cmd_engine",
    },
    {
        "id": "MUT-SCHED-02",
        "block": "scheduler",
        "file": "rtl/backend/ddr5_cmd_engine.sv",
        "description": "Đổi toán tử so sánh bù nợ refresh (owed_mis != thành ==)",
        "target": "wire        owed_mis  = (ref_owed != ~ref_owed_c);",
        "mutation": "wire        owed_mis  = (ref_owed == ~ref_owed_c);",
        "test": "tb_ddr5_cmd_engine",
    },
    {
        "id": "MUT-SCHED-03",
        "block": "scheduler",
        "file": "rtl/backend/ddr5_cmd_engine.sv",
        "description": "Đổi toán tử tăng bộ đếm burst ghi pacing (+ 1'b1 thành - 1'b1)",
        "target": "wr_burst_cnt <= wr_burst_cnt + 1'b1;",
        "mutation": "wr_burst_cnt <= wr_burst_cnt - 1'b1;",
        "test": "tb_ddr5_cmd_engine",
    },
    {
        "id": "MUT-SCHED-04",
        "block": "scheduler",
        "file": "rtl/backend/ddr5_cmd_engine.sv",
        "description": "Đảo điều kiện kiểm tra ngưỡng pacing ghi (>= thành <)",
        "target": "if (wr_burst_cnt >= 6'(WR_PACE_BURST - 1)) begin",
        "mutation": "if (wr_burst_cnt < 6'(WR_PACE_BURST - 1)) begin",
        "test": "tb_ddr5_cmd_engine",
    },
    {
        "id": "MUT-SCHED-05",
        "block": "scheduler",
        "file": "rtl/backend/ddr5_cmd_engine.sv",
        "description": "Làm sai cờ lỗi underflow nợ refresh (ref_owed == 3'd0 thành != 3'd0)",
        "target": "wire ref_uf_err   = ref_mode && (lat_kind == K_REF) && (ref_owed == 3'd0);",
        "mutation": "wire ref_uf_err   = ref_mode && (lat_kind == K_REF) && (ref_owed != 3'd0);",
        "test": "tb_ddr5_cmd_engine",
    },

    # -------------------------------------------------------------------------
    # 2. REORDER BUFFER (rtl/core/reorder_buffer_rob.sv) - Test: tb_reorder_buffer_rob
    # -------------------------------------------------------------------------
    {
        "id": "MUT-ROB-01",
        "block": "rob",
        "file": "rtl/core/reorder_buffer_rob.sv",
        "description": "Đảo điều kiện so sánh địa chỉ RAW hazard (== thành !=)",
        "target": "if (i_wr_active_addr[k*AXI_ADDR_WIDTH + 6 +: (AXI_ADDR_WIDTH-6)] == i_alloc_addr[AXI_ADDR_WIDTH-1:6]) begin",
        "mutation": "if (i_wr_active_addr[k*AXI_ADDR_WIDTH + 6 +: (AXI_ADDR_WIDTH-6)] != i_alloc_addr[AXI_ADDR_WIDTH-1:6]) begin",
        "test": "tb_reorder_buffer_rob",
    },
    {
        "id": "MUT-ROB-02",
        "block": "rob",
        "file": "rtl/core/reorder_buffer_rob.sv",
        "description": "Đảo tín hiệu sẵn sàng skid buffer (core_rready = skid_valid)",
        "target": "assign core_rready = !skid_valid;",
        "mutation": "assign core_rready = skid_valid;",
        "test": "tb_reorder_buffer_rob",
    },
    {
        "id": "MUT-ROB-03",
        "block": "rob",
        "file": "rtl/core/reorder_buffer_rob.sv",
        "description": "Bỏ kiểm tra RAW hazard khi cấp phát (alloc_ready bỏ qua o_raw_hazard)",
        "target": "assign o_alloc_ready = !o_rob_full && !o_raw_hazard;",
        "mutation": "assign o_alloc_ready = !o_rob_full || !o_raw_hazard;",
        "test": "tb_reorder_buffer_rob",
    },
    {
        "id": "MUT-ROB-04",
        "block": "rob",
        "file": "rtl/core/reorder_buffer_rob.sv",
        "description": "Đổi toán tử tăng beat writeback (+ thành -)",
        "target": "entry_wb_count[i_wb_tag] <= entry_wb_count[i_wb_tag] + 1'b1;",
        "mutation": "entry_wb_count[i_wb_tag] <= entry_wb_count[i_wb_tag] - 1'b1;",
        "test": "tb_reorder_buffer_rob",
    },
    {
        "id": "MUT-ROB-05",
        "block": "rob",
        "file": "rtl/core/reorder_buffer_rob.sv",
        "description": "Đổi toán tử tổng hợp tín hiệu RAW hazard (| thành &)",
        "target": "assign o_raw_hazard     = |raw_match_comb;",
        "mutation": "assign o_raw_hazard     = &raw_match_comb;",
        "test": "tb_reorder_buffer_rob",
    },

    # -------------------------------------------------------------------------
    # 3. AXI ADAPTER / BURST SPLITTER (rtl/frontend/axi_burst_splitter.sv) - Test: tb_axi_burst_splitter
    # -------------------------------------------------------------------------
    {
        "id": "MUT-ADAPT-01",
        "block": "adapter",
        "file": "rtl/frontend/axi_burst_splitter.sv",
        "description": "Đổi toán tử tính số word còn lại tới biên dòng (- thành +)",
        "target": "wire [LWB:0]         to_line   = (LWB+1)'(LW) - (LWB+1)'(addr[WB +: LWB]);",
        "mutation": "wire [LWB:0]         to_line   = (LWB+1)'(LW) + (LWB+1)'(addr[WB +: LWB]);",
        "test": "tb_axi_burst_splitter",
    },
    {
        "id": "MUT-ADAPT-02",
        "block": "adapter",
        "file": "rtl/frontend/axi_burst_splitter.sv",
        "description": "Đảo tín hiệu sẵn sàng nhận burst mới (o_ready = busy)",
        "target": "assign o_ready = !busy;",
        "mutation": "assign o_ready = busy;",
        "test": "tb_axi_burst_splitter",
    },
    {
        "id": "MUT-ADAPT-03",
        "block": "adapter",
        "file": "rtl/frontend/axi_burst_splitter.sv",
        "description": "Đổi toán tử trừ số beat còn lại (- thành +)",
        "target": "rem   <= rem - 9'(clen_q);",
        "mutation": "rem   <= rem + 9'(clen_q);",
        "test": "tb_axi_burst_splitter",
    },
    {
        "id": "MUT-ADAPT-04",
        "block": "adapter",
        "file": "rtl/frontend/axi_burst_splitter.sv",
        "description": "Đổi toán tử tính chiều dài xuất đoạn burst (- thành +)",
        "target": "o_len  <= 8'(clen_q) - 8'd1;",
        "mutation": "o_len  <= 8'(clen_q) + 8'd1;",
        "test": "tb_axi_burst_splitter",
    },
    {
        "id": "MUT-ADAPT-05",
        "block": "adapter",
        "file": "rtl/frontend/axi_burst_splitter.sv",
        "description": "Đảo điều kiện đánh dấu beat cuối o_last (== thành !=)",
        "target": "o_last <= (rem == 9'(clen_q));",
        "mutation": "o_last <= (rem != 9'(clen_q));",
        "test": "tb_axi_burst_splitter",
    },

    # -------------------------------------------------------------------------
    # 4. APB CSR REGISTERS (rtl/bus/apb_csr_regs.sv) - Test: tb_apb_csr_regs
    # -------------------------------------------------------------------------
    {
        "id": "MUT-CSR-01",
        "block": "csr",
        "file": "rtl/bus/apb_csr_regs.sv",
        "description": "Đảo kiểm tra quyền truy cập bảo mật pprot[1] (cho phép non-secure truy cập)",
        "target": "wire is_non_secure   = pprot[1];",
        "mutation": "wire is_non_secure   = !pprot[1];",
        "test": "tb_apb_csr_regs",
    },
    {
        "id": "MUT-CSR-02",
        "block": "csr",
        "file": "rtl/bus/apb_csr_regs.sv",
        "description": "Bỏ phát tín hiệu PSLVERR khi có truy cập vi phạm bảo mật",
        "target": "assign pslverr       = psel && penable && is_non_secure;",
        "mutation": "assign pslverr       = 1'b0;",
        "test": "tb_apb_csr_regs",
    },
    {
        "id": "MUT-CSR-03",
        "block": "csr",
        "file": "rtl/bus/apb_csr_regs.sv",
        "description": "Bỏ khóa reg_sec_locked khi ghi cấu hình (bỏ qua khóa an toàn)",
        "target": "if (!reg_sec_locked) begin",
        "mutation": "if (1'b1) begin",
        "test": "tb_apb_csr_regs",
    },
    {
        "id": "MUT-CSR-04",
        "block": "csr",
        "file": "rtl/bus/apb_csr_regs.sv",
        "description": "Làm rò rỉ dữ liệu cấu hình khi đang ở trạng thái khóa (bỏ che 0)",
        "target": "prdata = reg_sec_locked ? 32'h0 : reg_ext_config;",
        "mutation": "prdata = reg_sec_locked ? 32'hDEAD_BEEF : reg_ext_config;",
        "test": "tb_apb_csr_regs",
    },
    {
        "id": "MUT-CSR-05",
        "block": "csr",
        "file": "rtl/bus/apb_csr_regs.sv",
        "description": "Đảo điều kiện phát hiện lệch ray TMR (sec_locked_mismatch != thành ==)",
        "target": "wire         sec_locked_mismatch = (rail0_sec_locked != rail1_sec_locked) || (rail1_sec_locked != rail2_sec_locked);",
        "mutation": "wire         sec_locked_mismatch = (rail0_sec_locked == rail1_sec_locked) && (rail1_sec_locked == rail2_sec_locked);",
        "test": "tb_apb_csr_regs",
    },
]


def run_one_test(test_name: str, timeout: int = 30) -> tuple[bool, str]:
    """Chạy một testbench qua tools/run_one_tb.py và phân tích kết quả."""
    cmd = [sys.executable, str(ROOT / "tools" / "run_one_tb.py"), test_name, str(timeout)]
    try:
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout + 15)
        out = r.stdout + r.stderr
        if r.returncode != 0:
            return False, f"returncode={r.returncode}"
        if "[FAIL]" in out or "$fatal" in out or "FAILED" in out or "mismatch" in out.lower():
            return False, "test asserted failure"
        m = re.search(r"\[TB_RESULT\]\s+checks=(\d+)\s+fails=(\d+)", out)
        if m:
            fails = int(m.group(2))
            if fails > 0:
                return False, f"fails={fails}"
            return True, "checks pass"
        return True, "exit 0"
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except Exception as e:
        return False, f"exception: {e}"


def evaluate_mutant(mutant: dict) -> tuple[str, str]:
    """Áp dụng mutant vào RTL, chạy testbench tương ứng và hoàn nguyên file."""
    filepath = ROOT / mutant["file"]
    if not filepath.exists():
        return "ERROR", f"File khong ton tai: {filepath}"

    orig_bytes = filepath.read_bytes()
    orig_content = orig_bytes.decode("utf-8", errors="replace")
    target = mutant["target"]
    replacement = mutant["mutation"]

    if target not in orig_content:
        return "ERROR", f"Target pattern khong tim thay trong {mutant['file']}: '{target[:40]}...'"

    mutated_content = orig_content.replace(target, replacement, 1)

    try:
        # Ghi nội dung đột biến giữ nguyên line endings LF
        filepath.write_bytes(mutated_content.encode("utf-8"))

        # Chạy testbench đối chứng
        passed, reason = run_one_test(mutant["test"], timeout=20)

        # Nếu test FAIL -> Mutant bị bắt (KILLED)!
        # Nếu test PASS -> Mutant sống sót (SURVIVED)!
        if not passed:
            return "KILLED", reason
        else:
            return "SURVIVED", reason
    finally:
        # BẮT BUỘC: Hoàn nguyên RTL về trạng thái byte nguyên bản
        filepath.write_bytes(orig_bytes)


def main():
    parser = argparse.ArgumentParser(description="Q-Shield RTL Mutation Testing Engine")
    parser.add_argument("--module", choices=["scheduler", "rob", "adapter", "csr"], help="Chi chay cho 1 khoi")
    parser.add_argument("--dry-run", action="store_true", help="Liet ke mutant ma khong chay mo phong")
    parser.add_argument("--out", type=str, help="Duong dan luu bao cao JSON")
    args = parser.parse_args()

    active_mutants = MUTANTS
    if args.module:
        active_mutants = [m for m in MUTANTS if m["block"] == args.module]

    print("=" * 96)
    print("  Q-SHIELD SYNTHESIZABLE RTL MUTATION TESTING ENGINE")
    print(f"  Pham vi danh gia : {len(active_mutants)} mutants across scheduler, rob, adapter, csr")
    print(f"  Phuong phap chon : AST condition inversion, operator substitution, branch omission")
    print("=" * 96)

    if args.dry_run:
        for m in active_mutants:
            print(f"[{m['id']}] Block: {m['block']:<10} Test: {m['test']:<22} | {m['description']}")
        sys.exit(0)

    results = []
    killed_cnt = 0
    survived_cnt = 0
    error_cnt = 0

    print(f"{'Mutant ID':<13} | {'Block':<10} | {'Testbench':<22} | {'Result':<10} | {'Details'}")
    print("-" * 96)

    for m in active_mutants:
        t0 = time.time()
        status, details = evaluate_mutant(m)
        dt = time.time() - t0

        if status == "KILLED":
            killed_cnt += 1
            res_str = "KILLED"
        elif status == "SURVIVED":
            survived_cnt += 1
            res_str = "SURVIVED"
        else:
            error_cnt += 1
            res_str = "ERROR"

        print(f"{m['id']:<13} | {m['block']:<10} | {m['test']:<22} | {res_str:<10} | {details} ({dt:.1f}s)")
        m_copy = dict(m)
        m_copy["result"] = res_str
        m_copy["eval_details"] = details
        results.append(m_copy)

    print("-" * 96)
    total = len(active_mutants)
    score = (killed_cnt / total) * 100.0 if total > 0 else 0.0

    print(f"Tong so Mutants thu nghiem : {total}")
    print(f"So Mutant bi bat (KILLED)  : {killed_cnt}")
    print(f"So Mutant song sot (SURV)  : {survived_cnt}")
    print(f"So Mutant loi thuc thi     : {error_cnt}")
    print(f"Mutation Score Dat Duoc    : {score:.1f}%")

    if args.out:
        out_data = {
            "total": total,
            "killed": killed_cnt,
            "survived": survived_cnt,
            "mutation_score_pct": score,
            "mutants": results,
        }
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(out_data, f, indent=2)
        print(f"[+] Da xuat bao cao JSON: {args.out}")

    if survived_cnt > 0:
        print("\nDanh sach mutant song sot can giai thich kien truc:")
        for r in results:
            if r["result"] == "SURVIVED":
                print(f"  - [{r['id']}] {r['description']} ({r['file']})")

    # Yeu cau brief: >= 90% mutant bi bat
    if score >= 90.0:
        print(f"\n>>> KET QUA: MUTATION SCORE DAT TIEU CHUAN >= 90.0% ({score:.1f}%) (EXIT 0)")
        sys.exit(0)
    else:
        print(f"\n[!] MUTATION SCORE CHUA DAT 90%: {score:.1f}%")
        sys.exit(1)


if __name__ == "__main__":
    main()
