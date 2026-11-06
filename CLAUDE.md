# Q-Shield — hướng dẫn cho Claude Code

Quy tắc chung của dự án (RTL, bảo mật, kiểm chứng, chú thích, file header 2 dòng, thư mục chỉ lưu cục bộ) nằm trong
[AGENTS.md](AGENTS.md) và luôn được áp dụng. Mọi chỉnh sửa nằm trong `D:\RAM`; build tạm ở `build/` hoặc
`syn/reports/build/` (đã gitignore). Không commit khi chưa được yêu cầu.

## Multi-Agent Engineering Workflow

Khi được giao một task thiết kế, phân tích hoặc tối ưu phần cứng, Claude đóng vai **Lead Orchestrator** và điều phối
5 subagent trong `.claude/agents/` qua 5 phase theo đúng thứ tự. Phase 1–3 tuyệt đối không viết RTL.

| Phase | Agent (persona) | Đọc | Viết |
|---|---|---|---|
| 1 Micro-architecture spec | **spec-architect** (SoC & Memory Architect) | codebase | `docs/spec_v1.md` |
| 2a Adversarial review | **red-team-reviewer** (Hardware Security Critic) | `spec_v1.md`, RTL | `docs/review_and_testplan.md` |
| 2b Hardened spec v2 | **spec-architect** (gọi lần 2) | `spec_v1.md`, `review_and_testplan.md` | `docs/spec_v2.md` |
| 3a Verification plan | **verification-engineer** (Pre-Silicon Verification Lead) | `spec_v2.md`, `review_and_testplan.md` | `docs/verification_plan.md` |
| 3b Benchmark plan | **cmu-benchmark-architect** (CMU-SAFARI Benchmark Architect) | `spec_v2.md` | `docs/benchmark_plan.md` |
| 4 RTL + self-checking TB | **rtl-implementer** (Senior RTL Implementer) → **verification-engineer** | `spec_v2.md`, `review_and_testplan.md`, `verification_plan.md` | `rtl/`, `tb/` |
| 5 Benchmark so với thiết kế mẫu trong paper | **cmu-benchmark-architect** | `benchmark_plan.md`, `sim/results/PROVENANCE.md`, RTL đã pass | `tools/`, `sim/results/sota_benchmark/` |
| 6 Cập nhật paper | **cmu-benchmark-architect** | kết quả Phase 5, `paper/qshield_ieee.tex` | `paper/qshield_ieee.tex` (chỉ cục bộ) |

- 3a và 3b độc lập, chạy song song. Phase 4 lặp: verification-engineer gửi kịch bản lỗi về rtl-implementer tới khi
  pass 100%.
- Mặc định chạy liền Phase 1→5. **Cổng 2 bước:** nếu người dùng yêu cầu "review kiến trúc trước" (hoặc tương đương),
  dừng sau Phase 3, trình bày spec v2 + verification/benchmark plan và chờ người dùng "Approved" mới sang Phase 4.
- Không đồng thuận giả tạo: Phase 2a phải có ít nhất 4 lỗ hổng thật (kèm `file:dòng` hoặc kịch bản cụ thể), phủ cả
  mặt trận bảo mật (fault injection, side-channel, rò dữ liệu bus) và mặt trận bus/pipeline (deadlock, vòng tổ hợp
  `valid`/`ready`, read-during-write, write abort/rollback).
- Mọi cơ chế bảo mật (Parity, residue code, ECC, MAC, rollback) phải có phân tích timing trên đường đọc/ghi so với
  chu kỳ 2.5 ns (400 MHz) trong spec v2, và được xác nhận bằng synth khi chạm đường tới hạn.
- RTL và testbench hoàn chỉnh: không `// TODO`, không viết tắt `...`.

Orchestrator kiểm tra kết quả của từng phase (đọc tài liệu, diff, log mô phỏng/synth) trước khi chuyển phase, và báo
cho người dùng kết quả thật kể cả khi còn lỗi.

## Skill/agent bên ngoài (chọn lọc, giấy phép MIT)

Chép nguyên văn vào `.claude/`, chỉ phần liên quan; không chạy script đi kèm. Nguồn: `obra/superpowers`
(`systematic-debugging`, `verification-before-completion`, `writing-plans`, `test-driven-development`,
`requesting-code-review`, `receiving-code-review`, `dispatching-parallel-agents`) và `wshobson/agents`
(plugin `security-scanning`: agent `threat-modeling-expert`; skill `stride-analysis-patterns`,
`attack-tree-construction`, `threat-mitigation-mapping`, `security-requirement-extraction`). Giấy phép:
`.claude/skills/LICENSE-*.txt`. Dùng STRIDE/attack tree cho Phase 2a (red-team), debug/verification cho Phase 4.

## Công cụ của dự án

- Một testbench của regression: `python tools/run_one_tb.py <top> [timeout_s]` (build ở `build/one_<top>/`).
- Regression đầy đủ: `python run_iverilog_regression.py`; cocotb: `python run_all_tests.py`.
- Synth toàn top 400 MHz (xczu7ev, OOC): `vivado -mode batch -source syn/scripts/synth_top.tcl -tclargs <tag> [impl]`
  (Vivado: `C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat`, kết quả ở `syn/reports/build/`).
- Icarus Verilog `D:\iverilog\bin`: không hỗ trợ giá trị mặc định cổng phụ thuộc tham số hay `'1` trên cổng rộng
  (nối tường minh `{N{1'b1}}`), không có `break`, mảng localparam, task trả giá trị.
