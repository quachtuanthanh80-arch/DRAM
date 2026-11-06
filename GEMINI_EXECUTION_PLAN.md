# PLAN THỰC THI SỬA LỖI Q-SHIELD (dành cho model code Gemini)

- **Đầu vào:** [docs/verification_findings.md](docs/verification_findings.md), gồm 6 Critical, 13 High, 11 Medium, 4 nhóm Low. Mỗi finding có ID (C-n, H-n, M-n, L-n) và cột "Tin cậy": `[X]` đã xác nhận, `[A]` agent có bằng chứng nhưng chưa tái kiểm, `[R]` chỉ suy ra từ đọc mã.
- **Kết thúc khi:** `known_failing.txt` của `tb/findings/` rỗng, regression đầy đủ thoát 0 không còn XFAIL ẩn, 4 mục tiêu dưới đây đạt, và mọi số trong tài liệu truy được về file kết quả thật.
- **Mốc baseline:** 2026-11-06, commit `916b881` cộng working tree chưa commit (khoảng 166 file).
- **Người lập kế hoạch và review:** Claude. **Người viết code:** Gemini. Gemini không tự đổi quyết định ở mục 3.

### Bốn mục tiêu bắt buộc

| # | Mục tiêu | Đo bằng | Task |
|---|---|---|---|
| G1 | **Kết quả kiểm thử trung thực:** một nguồn số liệu regression duy nhất, không XFAIL che lỗi thật, XFAIL không cộng vào tổng check | `python run_iverilog_regression.py` (do người dùng/Claude chạy) | T01–T03 |
| G2 | **Đường dữ liệu thật:** top chuẩn có địa chỉ đúng xuống DRAM, đường đọc hoạt động, crypto nằm trên đường dữ liệu | `tb/findings/run_findings.py`, TB end-to-end | T10–T15, T30–T34 |
| G3 | **Mọi Critical/High có check tái hiện:** fail trước khi sửa, pass sau; môi trường UVM-style (pyuvm), SVA và formal | `tb/findings/`, `tb/uvm/`, `formal/` | T04, T60–T62 |
| G4 | **Tuyên bố = bằng chứng:** WNS ≥ 0 ở 2.5 ns bằng synth thật hoặc sửa claim theo số đo; benchmark không có nguồn bị gắn nhãn | `python tools/timing_gate.py --min-wns 0`, `tools/check_documentation_consistency.py` | T40, T41, T51 |

---

## 1. CÁCH DÙNG PLAN NÀY

**Mỗi session Gemini chỉ làm MỘT task.** Kéo đúng một file `briefs/<Txx>.md` vào chat (không kéo cả thư mục). Brief đã chứa mọi thứ cần
thiết (quy tắc, task, toàn văn finding). Nếu dùng plan này trực tiếp, dán prompt sau, thay `<Txx>`:

```text
Đọc GEMINI_EXECUTION_PLAN.md: mục 2 (quy tắc), mục 3 (quyết định), rồi task <Txx>.
Đọc dòng của từng finding trong "Finding" của task, trong docs/verification_findings.md.
Chỉ sửa các file trong "Được sửa" của task. Làm đúng các bước. Chạy mọi lệnh ở "Xong khi" và lưu
output thật vào reports/remediation/<Txx>.log. Gặp điều kiện dừng thì dừng và báo tôi.
Khi xong: tạo gói review build/review/<Txx>/ (mục 7.4), viết remediation_notes/<Txx>.md theo mẫu mục 7,
cập nhật remediation_notes/INDEX.md, chạy python tools/check_notes.py <Txx>, commit theo R8,
chạy python tools/safety_check.py --task <Txx> (phải thoát 0), rồi báo cáo: file đã sửa,
output từng tiêu chí, việc chưa làm được. Không tự chuyển sang task khác.
```

**Thứ tự:** theo cột "Phụ thuộc" ở mục 4 và danh sách trong `briefs/README.md`. Không nhảy làn. Task phụ thuộc một quyết định ở mục 3 mà quyết định
đó còn "Chưa chốt" thì **không được bắt đầu**.

**Task đánh dấu ⚠** là phần khó hoặc dễ sai âm thầm: Claude xem kế hoạch trước khi chạy và review diff trước khi nhận.

---

## 2. QUY TẮC BẮT BUỘC

| # | Quy tắc |
|---|---|
| R1 | **Không làm test "xanh" bằng cách yếu đi:** không nới assert/check, không hạ ngưỡng, không thêm skip/XFAIL, không tăng timeout để che hang, không `try/except` nuốt lỗi, không xóa test đang fail, không thu hẹp kích thích, không `$finish` sớm. |
| R2 | Chỉ đổi test cũ khi chính test đó mã hóa hành vi sai. Ghi trong commit và note: test nào, finding nào, vì sao hành vi cũ sai. |
| R3 | **Không có số gõ tay.** Mọi số trong report, README, bảng đều đọc từ file kết quả do lần chạy thật sinh ra. Không thay hằng số này bằng hằng số khác, không tạo số bằng "bảng cứng cộng nhiễu". |
| R4 | **Không bịa kết quả.** Output ở "Xong khi" là output thật, lưu vào `reports/remediation/<Txx>.log`. Chưa chạy được thì ghi `CHƯA CHẠY` kèm lý do. |
| R5 | Chỉ sửa file trong "Được sửa". Sửa file khác chỉ để giữ biên dịch (thêm cổng vào TB) thì được, nhưng liệt kê trong commit và note. Đổi logic ngoài danh sách thì dừng và báo. |
| R6 | Số dòng trong báo cáo có thể đã lệch (working tree thay đổi liên tục). Tìm vị trí theo **tên tín hiệu**, không theo số dòng. |
| R7 | Tuân thủ `AGENTS.md`: SystemVerilog tổng hợp được; `always_ff` dùng `<=`, `always_comb` dùng `=` và có `default`; không latch, không vòng tổ hợp; header 2 dòng; chú thích tiếng Việt chỉ cho cơ chế/ý tưởng/đánh đổi. Không `// TODO`, không `...`. **Icarus 12:** không `break`, không mảng localparam, không task trả giá trị, không giá trị mặc định cổng phụ thuộc tham số, không `'1` trên cổng rộng (viết `{N{1'b1}}`), không `force` lên phần tử mảng unpacked (dùng `$deposit` ở negedge), không `assert property` trong file Icarus biên dịch. |
| R8 | **Git:** chỉ làm việc trên nhánh `remediation/main`. Chỉ `git add <đường dẫn cụ thể>`; **cấm `git add -A` và `git add .`** (có `hwsec-repos/` 843 MB, `external_refs/`, `build/` chưa track). Mỗi task một commit, tiêu đề `fix(<Txx>): <mô tả> [C-3, H-2, ...]`. Không push, không force, không rebase, không amend, không reset, không checkout/restore, không clean. Sau commit tạo tag `rem/<Txx>`. |
| R9 | **Không đụng:** `paper/`, `tailieuthamkhao/`, `external_refs/`, `hwsec-repos/`, `downloads/`, `docs/spec_v1.md`, `docs/spec_v2.md`, `docs/review_and_testplan.md`, `docs/verification_plan.md`, `docs/verification_findings.md`, `GEMINI_EXECUTION_PLAN.md`, `GEMINI_SAFETY.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.claude/`, `.git/`, `.github/`, `LICENSE`, `build/sched_bench/rtl_v1/`. `tools/safety_check.py` kiểm điều này. |
| R10 | **Đóng timing bằng RTL, không bằng ràng buộc.** Cấm: nới chu kỳ 2.5 ns, thêm `set_false_path`/`set_multicycle_path` lên đường dữ liệu thật, đổi part khỏi `xczu7ev` để lấy số đẹp. Không đổi tên tín hiệu nội bộ nếu task không yêu cầu: TB truy cập phân cấp qua macro `qs_hier.svh`/`QS_T_*`. |
| R11 | **Mỗi task phải có file note** `remediation_notes/<Txx>.md` theo mẫu mục 7, commit cùng task. Thiếu note thì task chưa xong, kể cả khi mọi test pass. Task dừng giữa chừng vẫn phải có note ghi rõ dừng ở đâu. |
| R12 | **Task sửa RTL trên đường tới hạn** (ddr5_cmd_engine, axi_ddr5_mc_top, scheduler, crypto pipe) phải chạy `python tools/timing_gate.py` (có từ T40) và ghi WNS vào note. Trước T41: WNS không tụt quá 0,1 ns so với mốc tốt nhất trong `reports/remediation/timing_history.csv`. Từ T41: WNS ≥ 0. |
| R13 | **Không phá check đang đạt.** Đường cơ sở là `reports/remediation/baseline_failures.txt` (T02). FAIL mới ngoài danh sách đó = dừng, báo, không "sửa" bằng cách nới check. |
| R14 | **Tuân thủ và hiệu năng là có bằng chứng.** Cấm viết "100% PASS" khi còn XFAIL; cấm ghi Fmax/WNS/GE/throughput khi chưa có file kết quả đo trong repo; cấm viết "đạt" cho thuộc tính chưa có test. Chưa kiểm thì ghi "chưa kiểm" cùng lý do. |
| R15 | **Tách vai TB và RTL.** Phiên sửa RTL của một tính năng không được sửa TB kiểm chính tính năng đó, trừ thêm cổng để biên dịch (R5). Sửa RTL phải có check fail trước (reproduce) rồi pass sau; ghi cả hai dòng `[TB_RESULT] checks=.. fails=..` thật. |
| R16 | **Gói review đúng vị trí sửa** (mục 7.4) là điều kiện nộp. Thiếu gói hoặc diff có dòng ngoài `locations.txt` thì Claude trả task về, không review. |

**Điều kiện dừng chung** (dừng, ghi vào `reports/remediation/BLOCKED.md`, báo người dùng):
- Sau 3 lần sửa mà tiêu chí vẫn không đạt.
- Tiêu chí mâu thuẫn với finding, hoặc finding `[A]`/`[R]` không tái hiện được (báo, đừng sửa theo phỏng đoán).
- Cần quyết định còn "Chưa chốt" ở mục 3.
- Bản sửa làm hỏng một check trước đó đang đạt mà không rõ nguyên nhân.
- Cần chạm file ngoài "Được sửa" mà phải đổi logic; phát hiện file bị đổi/xóa mà mình không làm; số lượng `git status` đổi bất thường.

### Môi trường

| Công cụ | Trạng thái |
|---|---|
| Icarus Verilog 12 tại `D:\iverilog\bin`, Python 3.13, cocotb | Có. Chạy một TB: `python tools/run_one_tb.py <top> [timeout_s]` (build ở `build/one_<top>/`) |
| Vivado 2026.1 | `C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat`, không nằm trong PATH. Synth toàn top: `vivado -mode batch -source syn/scripts/synth_top.tcl -tclargs <tag> [impl]` (kết quả ở `syn/reports/build/`) |
| SymbiYosys, Verilator | Kiểm bằng `where sby`, `where verilator` trước khi hứa; chưa có thì ghi `CHƯA CHẠY` (R4) |
| pyuvm | Chưa cài cho dự án; T60 cài `pyuvm` và ghim phiên bản vào `requirements.txt` |

### Sự thật đã kiểm chứng, đừng làm ngược

- `sec_ddr5_controller_top.sv:620,627`: `qshield_crypto_top` có `i_precomp_valid=1'b0`, `i_wr_valid=1'b0` — crypto không nằm trên đường dữ liệu `[X]`.
- `sec_ddr5_controller_top.sv:445-449`: `req_row/req_col` lấy từ `fifo_a_rdata[127:96]` (bản mã), `req_is_write` hằng 1 `[X]`.
- `axi4_slave_adapter.sv:274-279`: `arready=1`, `rvalid=0` cố định — đường đọc của adapter là stub `[X]`.
- `ddr5_subchannel_scheduler.sv:154-176`: `bank_state/open_row` index theo `bank` (3 bit), không có BG `[X]`.
- `syn/reports/build/sched_v2b_timing.rpt`: WNS −0,282 ns ở 2.5 ns `[X]`. README/DESIGN.md ghi +0,142 ns/424,1 MHz không có báo cáo nào tương ứng.
- RS(18,16) và SECDED(72,64) đã được kiểm với mô hình Python độc lập: **đừng sửa** (xem "đã kiểm sạch" trong findings).
- `ddr5_cmd_engine` khớp tham số JEDEC DDR5 16Gb ở 2.5 ns (tRCD/tRP=7, tRAS=13, tRFC=118, tREFI=1560, tFAW=10). Đừng đổi.
- Hiện có 3 nguồn kết quả regression mâu thuẫn (`regression_summary.json` 38/40 cũ, `regression_logs/*.json`, golden 30/30). Đừng trích số nào trong đó cho tới khi T02 sinh lại.

---

## 3. QUYẾT ĐỊNH CỦA TÁC GIẢ (Gemini không tự đổi, không tự chốt)

| # | Câu hỏi | Đề xuất của Claude | Chặn task | Chốt |
|---|---|---|---|---|
| D1 | **Top nào là chuẩn:** `axi_ddr5_mc_top` hay `sec_ddr5_controller_top`? Nhiều lỗi nặng (C-1, C-3, C-4, H-1, M-4) nằm ở top thứ hai | Chọn `axi_ddr5_mc_top` làm chuẩn (là đường thật, được TB top và synth dùng); `sec_ddr5_controller_top` gắn nhãn "demo tích hợp crypto" hoặc đưa vào lộ trình hợp nhất ở T30 | T10, T11, T15, T30 | **Đã chốt 2026-11-06: `axi_ddr5_mc_top` là top chuẩn** (đúng đề xuất). `sec_ddr5_controller_top` là demo tích hợp crypto, không dùng cho số liệu/claim |
| D2 | Phạm vi crypto vòng này? | Bắt buộc: AES-XTS đúng (tweak mã hóa bằng K2) + MAC phủ đủ địa chỉ/bộ đếm. Profile CTR/split-counter nối vào đường dữ liệu chỉ khi D1 chọn `sec_ddr5_controller_top` | T30–T34 | **Chưa chốt** |
| D3 | Mục tiêu timing? | Giữ 400 MHz (2.5 ns), WNS ≥ 0 sau route trên `xczu7ev`. Nếu T41 làm hết các bước mà vẫn âm: **sửa claim theo số đo**, không nới chu kỳ, không đổi part | T40, T41, T51 | **Chưa chốt** |
| D4 | ZEM và RS chipkill chưa nối vào top: nối hay ghi giới hạn? | Ghi vào `LIMITATIONS.md`, sửa dossier; không nối ở vòng này | T50 | **Chưa chốt** |
| D5 | Bảng benchmark không có nguồn (22 468 MB/s, +29,86× BlockHammer, 58,4%…)? | Giữ file, gắn nhãn "chưa tái lập" ở mọi nơi trích; không xóa; không tự sinh số mới nếu chưa chạy lại Ramulator đã sửa | T51 | **Chưa chốt** |
| D6 | Cho Gemini commit trên nhánh `remediation/main` (R8)? `CLAUDE.md` hiện ghi "không commit khi chưa được yêu cầu" | Có, chỉ trên nhánh này, đường dẫn cụ thể, không push; T00 do người dùng tự chạy | tất cả | **Đã duyệt 2026-11-06.** Gemini commit chỉ trên `remediation/main`, đường dẫn cụ thể, không push. `CLAUDE.md` ("không commit khi chưa được yêu cầu") giữ nguyên cho Claude và phiên thường; ngoại lệ này chỉ áp dụng cho phiên Gemini làm theo brief |

Khi người dùng chốt, Claude cập nhật cột "Chốt" kèm ngày. Task có phụ thuộc quyết định chưa chốt giữ trạng thái KHÓA trong `briefs/README.md`.

---

## 4. TỔNG QUAN TASK

| Task | Tên | Phụ thuộc | Quyết định | Xong |
|---|---|---|---|---|
| **Làn 0: Lưới an toàn và hạ tầng đo** | | | | |
| T00 | Snapshot, nhánh, tag (người dùng tự chạy) | — | D6 ✔ | [ ] |
| T01 | Runner và đếm check trung thực | T00 | D6 | [ ] |
| T02 | Hợp nhất kết quả regression, baseline | T01 | — | [ ] |
| T03 | Golden verify thật, tham chiếu gãy | T01 | — | [ ] |
| T04 | Bộ check tái hiện finding `tb/findings` ⚠ | T02 | — | [ ] |
| T05 | Sửa TB rt02, rt03 (H-13, phần TB) | T02 | — | [ ] |
| T06 | Read starvation của ddr5_cmd_engine (rt01) ⚠ | T05 | — | [ ] |
| **Làn 1: Top và bus** | | | | |
| T10 | Phạm vi top chuẩn, nhãn top demo (đóng C-3, C-4, H-1 theo phạm vi) | T04 | D1 ✔ | [ ] |
| T11 | Rà soát đường chính `axi_ddr5_mc_top` theo lớp lỗi của top demo ⚠ | T10 | D1 ✔ | [ ] |
| T12 | Scheduler index {bg,bank} và tRAS/tWR/tFAW ⚠ | T04 | — | [ ] |
| T13 | RREADY của R channel (beat gửi 2 lần) | T04 | — | [ ] |
| T14 | WSTRB, bytes_total 4KB | T04 | — | [ ] |
| T15 | Thống nhất miền clock/top | T10 | D1 ✔ | [ ] |
| **Làn 2: CSR và khóa** | | | | |
| T20 | Khóa enc_enable, pprot, keys_valid | T04 | — | [ ] |
| T21 | Seed, ngưỡng, đọc ngược khóa, TMR sec_locked | T20 | — | [ ] |
| **Làn 3: Crypto** | | | | |
| T30 | Nối crypto vào `axi_ddr5_mc_top`, InvCipher ⚠ | T11, T20 | D1 ✔, D2 | [ ] |
| T31 | Tweak XTS đúng chuẩn IEEE 1619 ⚠ | T30 | D2 | [ ] |
| T32 | Scrambler có version | T30 | D2 | [ ] |
| T33 | Split counter ⚠ | T30 | D2 | [ ] |
| T34 | MAC phủ đủ địa chỉ/bộ đếm | T31, T33 | D2 | [ ] |
| **Làn 4: Timing** | | | | |
| T40 | Timing gate (WNS, LUT, FF) | T04 | D3 | [ ] |
| T41 | Đóng timing 2.5 ns ⚠ | T40, Làn 1–3 | D3 | [ ] |
| **Làn 5: Backend, tài liệu** | | | | |
| T50 | ZEM, chipkill: ghi giới hạn hoặc nối | T04 | D4 | [ ] |
| T51 | Số liệu và tuyên bố trong tài liệu ⚠ | T02, T40 | D3, D5 | [ ] |
| T52 | Logic chết và mục nhỏ | T04 | — | [ ] |
| **Làn 6: Môi trường verification** | | | | |
| T60 | Môi trường pyuvm (AXI, APB, scoreboard) ⚠ | T04 | — | [ ] |
| T61 | SVA và formal SymbiYosys | T04 | — | [ ] |
| T62 | Ma trận corner case, coverage, mutation | T60, T61 | — | [ ] |
| T70 | Nghiệm thu cuối | tất cả | — | [ ] |

**Cổng cuối mỗi làn:** `python tools/safety_check.py` thoát 0; `python tb/findings/run_findings.py` thoát 0 (sau T04); người dùng/Claude chạy `python run_iverilog_regression.py`; tag `remediation-lan-<n>`; Claude review theo mục 7.3 trước khi sang làn sau.

---

## 5. CHI TIẾT TASK

### LÀN 0: LƯỚI AN TOÀN VÀ HẠ TẦNG ĐO

#### T00. Snapshot, nhánh, tag (người dùng tự chạy, Gemini không làm)
- **Finding:** không có finding riêng.
- **Được sửa:** chỉ thao tác git; tạo `reports/remediation/`.
- **Vì sao người dùng tự chạy:** commit toàn bộ thay đổi đang dở (khoảng 166 file, gồm xóa `GOLDEN_OUTPUTS/*`, `sim/results/*`, `sim/traces/*`, `rtl/backend/gf16_arith_pkg.sv`).

1. Sao lưu ngoài repo (xem `GEMINI_SAFETY.md` mục 1) và chạy `python tools/safety_check.py --init`.
2. Kiểm `git status --short | wc -l`; khác nhiều 166 thì dừng.
3. `git switch -c remediation/main`; `git add -u`; thêm có chọn lọc các file mới cần theo dõi (`GEMINI*.md`, `tools/safety_check.py`, `tools/check_notes.py`, `tools/make_briefs.py`, `briefs`, `remediation_notes`, `docs/verification_findings.md`). **Không add** `hwsec-repos/`, `external_refs/`, `build/`, `paper/`, `tailieuthamkhao/`.
4. `git diff --cached --stat | tail -5`: không file nào trên 5 MB. Commit `chore(T00): snapshot pre-remediation`, `git tag pre-remediation`.
5. `git remote set-url --push origin DISABLED` để vô hiệu đẩy lên remote.
- **Xong khi:** `python tools/safety_check.py` thoát 0; tag `pre-remediation` tồn tại; push URL là `DISABLED`.

#### T01. Runner và đếm check trung thực
- **Finding:** H-11, M-9.
- **Được sửa:** `tb/common/tb_check.svh` (hoặc file định nghĩa `tb_check_xfail`: tìm bằng `grep -rn "tb_check_xfail" tb/`), `run_iverilog_regression.py`, `run_all_tests.py`, `tb/bus/tb_axi4_slave_adapter.sv` (chỉ dòng gọi XFAIL), `tools/check_gate.py` (mới).

1. `tb_check_xfail` không được tăng `tb_checks`; đếm XFAIL ở biến riêng và in `[TB_RESULT] checks=N fails=F xfails=X`. Cập nhật bộ phân tích trong `run_iverilog_regression.py` đọc `xfails` riêng; tổng báo cáo ghi "PASS (kèm X XFAIL)" và liệt kê ID XFAIL (R1, R4, R6, S23…), không gộp vào "pass rate 100%".
2. `subprocess.run` của runner phải có `timeout=` (tham số `--timeout`, mặc định 600 s cho mỗi TB); hết giờ = `TIMEOUT` = FAIL. Thu hẹp phát hiện `fatal`: chỉ khớp `$fatal` hoặc dòng bắt đầu bằng `FATAL` / `[FAIL]`, không khớp chữ "fatal" tùy ý trong log.
3. `tools/check_gate.py`: một TB tí hon cố ý fail và một TB cố ý treo, chạy qua runner; **thoát 0 chỉ khi runner báo FAIL cho cả hai**. Thêm làm bước đầu của `run_all_tests.py`.
- **Xong khi:** `python tools/check_gate.py` thoát 0. Thêm tạm `$fatal` vào một TB, runner báo FAIL đúng TB đó; hoàn nguyên và `git diff` xác nhận. XFAIL không cộng vào checks (chứng minh bằng `tb_sec_ddr5_controller_top`: tổng checks giảm đúng bằng số XFAIL). **Không sửa các lỗi RTL mà task này làm lộ ra.**

#### T02. Hợp nhất kết quả regression, baseline
- **Finding:** H-9, H-10.
- **Được sửa:** `regression_summary.json` (file sinh), `regression_logs/` (file sinh), `reports/remediation/baseline_failures.txt` (mới), `run_iverilog_regression.py` (chỉ chọn đường ghi).
- **Lệnh dài ~30 phút:** chạy nền, timeout runner 45 phút, lưu log. Đây là lần chạy full duy nhất Gemini được phép (xem `GEMINI_SAFETY.md` mục 3).

1. Chỉ giữ **một** nguồn kết quả: `regression_summary.json` ở gốc, do `run_iverilog_regression.py` sinh. `regression_logs/failure_report.json` và `regression_logs/regression_summary.json` cũ (31/10) phải bị ghi đè hoặc được runner ghi kèm cờ `stale=true`; không để ba file mâu thuẫn tồn tại.
2. Chạy lại full regression trên RTL hiện tại. Ghi `baseline_failures.txt`: mỗi dòng một TB FAIL kèm một dòng lỗi đầu tiên (`tb_rt01_ref_starvation`, `tb_rt02_credit_race`, `tb_rt03_rd_integrity`, `tb_eng_v2_random` nếu còn).
3. H-10: chạy `python tools/run_one_tb.py tb_eng_v2_random 200`; ghi kết quả thật. Nếu còn 14 `ENGCHK-ERR` thì đó là hồi quy thật: **không nới `qs_engine_port_chk`**, ghi vào BLOCKED.md và dừng phần đó.
4. Ghi số test đăng ký, số pass/fail/xfail, commit hash vào `regression_summary.json` (trường đã có: `commit_sha`, `timestamp_epoch`).
- **Xong khi:** `regression_summary.json` có `total_tests` bằng số TB script đăng ký (kiểm `grep -c` danh sách trong script); `baseline_failures.txt` tồn tại; không còn hai file kết quả cũ mâu thuẫn.
- **Dừng nếu:** regression hết 45 phút hoặc crash trình mô phỏng.

#### T03. Golden verify thật, tham chiếu gãy
- **Finding:** H-12, M-11.
- **Được sửa:** `tools/verify_golden_outputs.py`, `GOLDEN_OUTPUTS/README.md`, `GOLDEN_OUTPUTS/checksums.sha256`, `REPRODUCIBILITY.md`, `sim/README.md`, `sim/run_ddr5_6000.py`.

1. `verify_golden_outputs.py` phải truyền `key_numeric_fields` (total, passed, failed, xfails, commit) và **thoát 1** khi golden lệch regression hiện hành hoặc khi chỉ kiểm "JSON tải được". Kiểm chứng: sửa một số trong bản sao golden thì script FAIL.
2. `checksums.sha256` không được còn dòng trỏ file đã xóa; `sha256sum -c` phải sạch.
3. `REPRODUCIBILITY.md`, `sim/README.md`: bỏ tham chiếu `bench_metrics.csv`, `bench_summary.json`, `apples_to_apples_cycle_accurate.*` nếu đã bị gỡ khỏi golden (theo `GOLDEN_OUTPUTS/README.md`); ghi rõ chúng là đầu ra của `sim/run_benchmarks.py`, sinh lại được, chưa có bản golden. Thay đường dẫn WSL tuyệt đối `/mnt/d/RAM/...` bằng đường dẫn tương đối.
4. Mọi con số "30/30", "19", "14", "20 suites" trong các file trên: **không tự sửa thành số khác**; để T51 xử lý sau khi T02 có số thật. Chỉ ghi chú `<!-- số cũ, chờ T51 -->`.
- **Xong khi:** `python tools/verify_golden_outputs.py` thoát 1 khi cố ý lệch một số (hoàn nguyên) và thoát 0 khi nhất quán; `sha256sum -c GOLDEN_OUTPUTS/checksums.sha256` sạch.

#### T04. Bộ check tái hiện finding `tb/findings` ⚠
- **Finding:** C-1, C-2, C-3, C-4, H-1, H-2, H-3, H-4, H-5, H-6, H-7, H-8.
- **Được sửa:** `tb/findings/**` (mới), `run_all_tests.py`. **Không sửa `rtl/`.**

Mỗi finding có kịch bản rõ thành một check **fail trên RTL hiện tại**. Cấu trúc:
```text
tb/findings/
  run_findings.py        chạy mọi check, đọc known_failing.txt
  known_failing.txt      mỗi dòng một id check còn mở
  checks/<id>.sv|.py     một check cho một finding
```
1. `run_findings.py` thoát 1 khi: check ngoài danh sách bị fail, **hoặc** check trong danh sách lại pass (buộc xóa khỏi danh sách khi đã sửa). Thêm làm bước của `run_all_tests.py`.
2. Check nào của finding `[A]`/`[R]` không tái hiện được trên RTL hiện tại: ghi `not_reproduced` trong `reports/remediation/T04_unreproduced.txt` và **dừng phần đó, báo Claude**. Không viết check luôn-fail.
3. Kịch bản gợi ý (mỗi cái một check): C-1 `o_wr_valid` của `qshield_crypto_top` không bao giờ lên khi AXI ghi; C-3 địa chỉ DFI ≠ địa chỉ AXI đã ánh xạ; C-4 `ARVALID` không bao giờ có `RVALID`; H-1 `soft_reset` giữa burst làm FIFO còn entry cũ (ba check này viết trên `sec_ddr5_controller_top` để xác nhận lỗi tồn tại; vì D1 coi top này là demo, chúng ghi vào `tb/findings/known_open_demo.txt`, không vào `known_failing.txt`; check tương ứng trên đường chính thuộc T11); H-2 WR bg1/ba0 phát khi chưa ACT; H-3 `RREADY=0` làm beat R lặp; H-4 ghi `CTRL[0]=0` sau `sec_locked`; H-5 ghi APB với `pprot` non-secure vẫn nạp được khóa; H-6 đọc ngược `AddrScrambleSeed`; H-7 ghi hai lần cùng địa chỉ cho cùng mask; H-8 `minor=127` giải mã sai.
4. File sinh ra nằm trong `build/findings/`.
- **Xong khi:** `python tb/findings/run_findings.py` thoát 0 với `known_failing.txt` chứa đúng các lỗi còn mở; xóa một dòng khỏi danh sách thì thoát 1. Lưu bảng kết quả vào log.

#### T05. Sửa TB rt02, rt03 (H-13, phần TB)
- **Finding:** H-13.
- **Được sửa:** `tb/top/tb_rt02_credit_race.sv`, `tb/top/tb_rt03_rd_integrity.sv`, `tb/common/dfi_rd_fault_shim.sv`. **Không sửa `rtl/`.**

Hai lỗi đã chẩn đoán trong `docs/gemini_phase4_r1.md` (đọc chỉ T1 và T2, dừng trước §5):
1. **`tb_rt02`:** `T-RT02a coverage ... hit 0 times (min 20)` — kích thích chưa chạm tình huống `rd_fire && wr_fire` cùng BG khi `sum(bk_cnt) ≥ 7`. Gửi 6–7 lệnh ghi tới các hàng khác nhau của cùng BG tới khi tổng `bk_cnt` = 6; gửi 1 lệnh đọc tới BG đó, ngay chu kỳ sau gửi 1 lệnh ghi cùng BG; lặp ≥ 20 lần, seed cố định. Tối đa 3 lần chỉnh; vẫn 0 trúng thì dừng và báo `max(sum bk_cnt)`.
2. **`tb_rt03` T-RT03d:** chẩn đoán cho thấy TB arm sai RD (RD của scrubber/lệnh đọc không phải RMW). Arm **sau** khi `dut.u_cmd_engine.s_rmw != 0` và xác nhận `cas_rmw_q = 1`; tách kiểm gộp thành 3 điều riêng (`rresp != 00 || rpoison`, `rdata == 0`, in 3 trường). Nếu arm đúng RD của RMW mà vẫn FAIL: **dừng, không sửa RTL**, báo các tín hiệu liệt kê trong T2 §5 của tài liệu đó.
- **Xong khi:** `tb_rt02` 4/4 và `tb_rt03` 18/18 (hoặc dừng có báo cáo rõ); `tb_rt01` vẫn FAIL là đúng (thuộc T06); `git diff` chỉ chạm 3 file được sửa; không nới check.

#### T06. Read starvation của ddr5_cmd_engine (tb_rt01) ⚠
- **Finding:** H-13.
- **Được sửa:** `rtl/backend/ddr5_cmd_engine.sv`.
- **Thiết kế do Claude chốt (M-13), Gemini không đổi:** cờ đói đọc. Nếu có lệnh đọc đã sẵn sàng trong engine chờ quá `RD_STARVE_MAX` chu kỳ liên tục, chặn phát CAS ghi **mới** tới khi một CAS đọc được phát. **Không thêm mức logic vào đường theo bank** (engine đang WNS âm; R12).

1. Tham số `RD_STARVE_MAX = 96` (hợp lệ 16..1023), thêm vào assert elaboration SA-E09 hiện có.
2. Trạng thái `rd_wait_cnt[9:0]`, `rd_starve_q`; reset trong khối reset. Bộ đếm tăng khi tồn tại lệnh đọc đã sẵn sàng bị chặn, về 0 khi một CAS đọc phát.
3. `rd_starve_q` chỉ gate việc **chọn CAS ghi** ở tầng chọn lệnh, không chạm đường chọn đọc.
4. Chỉ đọc đúng dải bằng `grep -n "rd_ok_g\|wr_ok_g\|sel_is_wr\|pk_oh" rtl/backend/ddr5_cmd_engine.sv` rồi `sed -n 'a,bp'`; không đọc nguyên file (73 KB).
- **Xong khi:** `tb_rt01_ref_starvation` 8/8; `tb_ddr5_cmd_engine`, `tb_mcsee_autonomous_rfm`, `tb_rowpress_tras_clamping`, `tb_prac_abo_phoenix`, `tb_rt04_jedec_400mhz`, `tb_eng_*`, `tb_drm_*` vẫn như `baseline_failures.txt`; có dòng reproduce (fail trước) và pass sau.
- **Dừng nếu:** WNS tụt quá 0,1 ns (R12) hoặc test cũ đang pass bị đỏ.

### LÀN 1: TOP VÀ BUS (D1 đã chốt: `axi_ddr5_mc_top` là top chuẩn)

Mọi task làn này: `python tb/findings/run_findings.py` phải xóa dòng finding tương ứng khỏi `known_failing.txt` (R15) và không có FAIL mới (R13).

#### T10. Phạm vi top chuẩn, nhãn top demo
- **Finding:** C-3, C-4, H-1.
- **Được sửa:** `rtl/top/sec_ddr5_controller_top.sv` (chỉ header 2 dòng và chú thích), `LIMITATIONS.md`, `README.md` (chỉ đoạn nhắc tới top này), `rtl/README.md` (nếu chưa có thì tạo), `run_iverilog_regression.py` (chỉ nhãn tên test), `tb/findings/checks/**` (mới).
- **Theo D1 (đã chốt):** `sec_ddr5_controller_top` là demo tích hợp crypto, không phải đường chính. C-3 (địa chỉ lấy từ bản mã), C-4 (đường đọc stub) và H-1 (reset FIFO lệch) **được đóng theo phạm vi, không sửa RTL**; vẫn ghi đủ vào `LIMITATIONS.md`.

1. Lập danh sách mọi nơi dùng top này: `grep -rn "sec_ddr5_controller_top" . --include=*.py --include=*.tcl --include=*.md --include=*.f --include=*.sv` (loại `hwsec-repos/`, `external_refs/`, `.agents/`, `build/`). Đã biết: `run_iverilog_regression.py`, `syn/create_vivado_project.tcl`, `syn/run_synth.tcl`, `synth/asic/README.md`, `PEER_REVIEW_DEFENSE_DOSSIER.md`, `docs/verification_plan.md`. Ghi bảng "nơi dùng → có số liệu/claim nào lấy từ top này không" vào note.
2. Nơi nào số liệu (Fmax, GE, LUT, throughput) lấy từ synth của top demo mà tài liệu gán cho top chuẩn: **dừng phần đó và báo Claude** (đây là bất nhất tuyên bố, thuộc T51).
3. Gắn nhãn: header 2 dòng của top demo ghi rõ "demo tích hợp crypto, chưa dùng cho số liệu"; `LIMITATIONS.md` liệt kê C-3, C-4, H-1 kèm cách tái hiện; test `tb_sec_ddr5_controller_top` đổi nhãn "demo". Không xóa file, không xóa TB.
4. Check `tb/findings` xác nhận không module nào của đường chính (`axi_ddr5_mc_top` và cây instance của nó) instantiate `sec_ddr5_controller_top`.
- **Xong khi:** check trên pass; `LIMITATIONS.md` có 3 mục; bảng "nơi dùng" đầy đủ; `git diff` không chạm logic RTL.

#### T11. Rà soát đường chính `axi_ddr5_mc_top` theo lớp lỗi của top demo ⚠
- **Finding:** C-3, C-4, H-1 (phiên bản trên đường chính).
- **Được sửa:** `tb/findings/checks/**`, `tb/top/tb_axi_ddr5_mc_top.sv` (chỉ thêm scoreboard/check, không nới check cũ), `rtl/top/axi_ddr5_mc_top.sv` (chỉ khi check chứng minh lỗi thật), `rtl/cdc/rst_sync.sv`.
- **Mục đích:** audit VC chưa duyệt hết `axi_ddr5_mc_top.sv`. Kiểm ba lớp lỗi tương tự trên đường chính:
  1. **Địa chỉ DRAM thật:** scoreboard so địa chỉ (bank, BG, row, col) tại DFI với AWADDR/ARADDR đã qua `addr_mapper_ddr5`, với ghi và đọc, 1000 giao dịch ngẫu nhiên có seed.
  2. **Đường đọc sống:** mọi AR có đủ R (RVALID, RLAST đúng số beat), không treo; kiểm cả `RREADY` ngẫu nhiên (liên quan H-3/T13).
  3. **Reset:** nếu có `soft_reset` hay reset tổ hợp trên đường chính, kiểm xung `soft_reset` giữa burst không để lại entry ma ở FIFO/ROB. Thêm `STAGES >= 2` bằng assert elaboration trong `rst_sync` (L-2).
- Check nào **fail trên đường chính** là finding thật: ghi vào `known_failing.txt`, báo Claude để mở task sửa; **không tự sửa RTL ngoài danh sách**. Check pass là lá chắn chống hồi quy ("không được xấu đi").
- **Xong khi:** ba nhóm check chạy trên `axi_ddr5_mc_top` với kết quả thật (pass hoặc fail có ghi); báo cáo trong note kèm `[TB_RESULT]`; `rst_sync` có assert.

#### T12. Scheduler index {bg,bank} và tRAS/tWR/tFAW ⚠
- **Finding:** H-2, M-1.
- **Được sửa:** `rtl/memory/ddr5_subchannel_scheduler.sv`.

1. `bank_state`/`open_row` index theo `{bank_grp, bank}` (32 phần tử). Kiểm tra mọi chỗ dùng `bank` làm chỉ mục.
2. Thêm bộ đếm tRAS (13), tWR, tRRD/tFAW theo cùng giá trị đã khớp JEDEC trong `ddr5_cmd_engine` (đọc tham số từ gói chung nếu có; **không tự viết số JEDEC từ trí nhớ** — mâu thuẫn thì báo).
3. Nếu scheduler này không thuộc đường chính (D1), vẫn sửa H-2 (lỗi chỉ mục) nhưng M-1 ghi "không áp dụng: scheduler không trên đường chính" kèm bằng chứng `grep` instance.
- **Xong khi:** check H-2 pass; SVA: RD/WR chỉ phát khi `open_row[bg,ba]` đã ACT; `tb_rt04_jedec_400mhz` vẫn pass.

#### T13. RREADY của R channel
- **Finding:** H-3.
- **Được sửa:** `rtl/top/axi_ddr5_mc_top.sv` (chỉ phần nối `i_rready`/`o_rdata_ready`), `rtl/frontend/axi_slave_frontend.sv`, `rtl/core/reorder_buffer_rob.sv`.

1. Nối `i_rready` của ROB với `o_rdata_ready` của skid ở frontend, hoặc bỏ skid ở một phía; **không** để cả hai cùng giữ bản sao beat.
2. Thêm cổng hoặc tham số cần thiết cho TB `tb_axi_ddr5_mc_top` để chạy với `RREADY` ngẫu nhiên có seed (TB là của T60; ở đây chỉ thêm check trong `tb/findings`).
- **Xong khi:** check H-3 pass: số beat R == số beat ROB retire với `RREADY` ngẫu nhiên, mọi RID/RLAST đúng; mc_top 14/14 như baseline.

#### T14. WSTRB, bytes_total 4KB
- **Finding:** M-2, M-3.
- **Được sửa:** `rtl/bus/axi4_slave_adapter.sv`, `rtl/frontend/axi_slave_frontend.sv`, `rtl/memory/dfi_phy_adapter.sv`.

1. Mang WSTRB tới `dfi_wrdata_mask` hoặc RMW; kiểm `WLAST` đúng beat `AWLEN`; sai thì `SLVERR`.
2. `bytes_total` 16 bit và tính theo loại burst (FIXED/INCR/WRAP); dùng cờ `cross_4kb` để trả `SLVERR` hoặc tách burst (chọn một, ghi vào note), không để hở.
- **Xong khi:** burst 8192 B cho cờ đúng; ghi từng phần không ghi đè byte khác; `tb_axi4_slave_adapter` pass.

#### T15. Thống nhất miền clock/top
- **Finding:** M-4, L-2.
- **Được sửa:** `rtl/top/axi_ddr5_mc_top.sv`, `rtl/interfaces/*.sv` (chỉ cổng).
- **Theo D1 (đã chốt):** chỉ xét `axi_ddr5_mc_top`. `clk_ddr`/`rst_n_ddr` hiện chỉ vào `rst_sync` rồi sink. Chốt một kiến trúc: nếu cần miền DDR thì thêm CDC thật (FIFO Gray); nếu không thì xóa cổng thừa và ghi rõ "một miền clock". Dọn logic chết `rob_raw_hazard` (L-2) hoặc nối thật. Đổi cổng top phải cập nhật mọi TB/shim instantiate (R5: chỉ để giữ biên dịch).
- **Xong khi:** lint không còn cổng treo; mô tả miền clock trong `DESIGN.md` khớp RTL.

### LÀN 2: CSR VÀ KHÓA

#### T20. Khóa enc_enable, pprot, keys_valid
- **Finding:** H-4, H-5.
- **Được sửa:** `rtl/bus/apb_csr_regs.sv`, `rtl/interfaces/pcie_cxl_io_apb_shim.sv`.

1. Sau `sec_locked`, `enc_enable` và `soft_reset` không ghi được (hoặc chỉ qua thanh ghi ghi-một-lần có reset); thay đổi giữa burst không được xảy ra (chốt theo burst, không theo beat).
2. Kiểm `pprot` (bit secure) như `multi_vm_key_table`; ghi sai trả `pslverr=1`. Khi `!keys_valid` chặn lưu lượng (`pipe_in_valid=0`) thay vì mã hóa bằng khóa 0.
- **Xong khi:** check H-4, H-5 pass; SVA `sec_locked |-> $stable(enc_enable)` và `!keys_valid |-> !pipe_in_valid` (trong file formal/xsim, không trong file Icarus: R7); `tb_apb_csr_regs` pass.

#### T21. Seed, ngưỡng, đọc ngược khóa, TMR sec_locked
- **Finding:** H-6, M-6.
- **Được sửa:** `rtl/bus/apb_csr_regs.sv`, `rtl/core/fault_hardened_csr.sv`, `rtl/top/sec_ddr5_controller_top.sv` (chỉ nối cảnh báo).

1. K1/K2 chỉ-ghi (đã che sau lock; phải che cả trước lock). `AddrScrambleSeedL/H`, `AddrExtConfig`, ngưỡng RowHammer vào phạm vi `sec_locked`; seed không đọc lại được.
2. `reg_sec_locked` bảo vệ bằng TMR, fail-closed (glitch ⇒ khóa, không mở); nối `o_glitch_alert`, `o_tmr_alert` ra cổng. Đầu ra `tmr_*` phải điều khiển thật các thanh ghi tương ứng.
- **Xong khi:** check H-6 pass (`prdata` không phụ thuộc khóa/seed ở mọi địa chỉ); fault injection lật 1 bit `sec_locked` không mở khóa; `tb_fault_hardened_csr` pass.

### LÀN 3: CRYPTO (D1 đã chốt; KHÓA tới khi D2 chốt)

#### T30. Nối crypto vào `axi_ddr5_mc_top`, InvCipher ⚠
- **Finding:** C-1.
- **Được sửa:** `rtl/top/axi_ddr5_mc_top.sv`, `rtl/crypto/qshield_crypto_top.sv`, `rtl/crypto/multi_vm_key_table.sv`, `rtl/crypto/subchannel_aes_xts_pipe.sv`, file InvCipher mới `rtl/crypto/aes128_dec_iter.sv`.
- **Theo D1 (đã chốt):** top chuẩn là `axi_ddr5_mc_top`; ở đó `qshield_crypto_top` **chưa được instantiate** và `multi_vm_key_table` (dòng ~940) có APB nối hằng 0. Cần D2. Việc lớn: Claude viết đặc tả riêng (`docs/spec_crypto_integration.md`: vị trí chèn crypto giữa frontend và scheduler, độ trễ thêm, giao diện valid/ready, đường đọc) trước khi Gemini bắt đầu; nếu đặc tả chưa có thì dừng.

1. Instantiate crypto trong `axi_ddr5_mc_top` theo đặc tả; nối ghi/đọc, APB và ASID vào nguồn thật (CSR T20); `valid` của key table dẫn tới `keys_valid`.
2. Thêm giải mã AES (InvCipher) cho đường đọc; kiểm bằng KAT FIPS-197.
3. Không tạo vòng tổ hợp valid/ready; giữ zero-bubble hoặc ghi độ trễ thêm vào note. Đây là thay đổi lớn trên đường tới hạn: R12 áp dụng.
- **Xong khi:** TB ghi rồi đọc lại khớp qua mã hóa/giải mã; check C-1 pass; DRAM model thấy bản mã ≠ bản rõ khi `enc_enable=1`; KAT AES pass; WNS ghi vào note (R12).

#### T31. Tweak XTS đúng chuẩn IEEE 1619 ⚠
- **Finding:** C-2.
- **Được sửa:** `rtl/crypto/subchannel_aes_xts_pipe.sv`, `rtl/crypto/aes_tweak_gen.sv`, `rtl/bus/axi4_slave_adapter.sv` (chỉ phần tạo tweak).
- **Cần D2.** Tweak = AES_K2(địa chỉ đầy đủ ‖ ASID ‖ version) nhân α^j theo vị trí khối; K2 thực sự dùng (không trong `_unused_top`).
- **Xong khi:** vector IEEE 1619 và `tools/gen_xts_kat.py` khớp bit-bit; check C-2 pass (chép C từ a sang a' không cho bản rõ sửa đổi có kiểm soát); SVA `tweak` không là hàm công khai của địa chỉ.

#### T32. Scrambler có version
- **Finding:** H-7.
- **Được sửa:** `rtl/memory/bus_scrambler.sv`, `rtl/memory/scrambler_ks_pipe.sv`, `rtl/core/scarf_dram_randomizer.sv` (chỉ nhập version).
- **Cần D2.** Keystream phụ thuộc `(seed, địa chỉ, kênh/rank, version)`; hoặc giữ như hiện tại và **ghi rõ "chống pattern, không phải mã hóa"** trong spec và README. Chọn theo D2, ghi vào note.
- **Xong khi:** hai ghi cùng địa chỉ cho mask khác nhau (nếu có version); đọc vùng toàn 0 không lộ mask dùng lại; kiểm thống kê.

#### T33. Split counter ⚠
- **Finding:** H-8.
- **Được sửa:** `rtl/crypto/split_counter_table.sv`, `rtl/crypto/qshield_crypto_top.sv`.
- **Cần D2.** Tăng major ngay ở bước tra cứu; bảng "pending" theo dòng để hai ghi cùng dòng không trùng `eff_minor`; khi minor tràn, tạo trạng thái re-encrypt cho 63 dòng còn lại; profile 2: `o_wr_ready` chỉ khi keystream sẵn sàng; chặn đổi khóa khi pipeline đang bay.
- **Xong khi:** SVA/formal BMC: tính duy nhất của `(major, minor, addr)`; check H-8 pass (minor=127 ghi rồi đọc đúng); không two-time pad.

#### T34. MAC phủ đủ địa chỉ/bộ đếm
- **Finding:** M-5.
- **Được sửa:** `rtl/crypto/integrity_mac_gen.sv`, `rtl/crypto/qshield_crypto_top.sv`.
- **Cần D2.** MAC phủ địa chỉ 34-bit đầy đủ, bộ đếm đầy đủ, key_id; dùng khóa riêng (không dùng chung K2 với tweak); chỉ mục `tag_ctr[i_wr_tag]` giới hạn 0..15.
- **Xong khi:** A và A+4GB cho MAC khác nhau; dời chỗ bị phát hiện; không chỉ mục vượt biên.

### LÀN 4: TIMING

#### T40. Timing gate
- **Finding:** C-5 (phần công cụ).
- **Được sửa:** `tools/timing_gate.py` (mới), `syn/scripts/timing_gate.tcl` (mới).
- **Cần D3.**

1. `timing_gate.py` gọi Vivado (đường dẫn trong mục Môi trường) cho top chuẩn (D1), đọc WNS/TNS/LUT/FF/BRAM/DSP từ báo cáo, in bảng, ghi `reports/remediation/timing_history.csv` kèm commit hash. Tham số `--min-wns`; thoát 1 khi WNS thấp hơn ngưỡng.
2. Chạy trong `syn/reports/build/<tag>/` (đã gitignore), không đè báo cáo hiện có. Đo cả sau synth và (tùy chọn) sau `impl`.
3. Ghi mốc đầu tiên cùng lý do: số đo hiện có là −0,282 ns (sched_v2b) và −0,611 ns (top14); không tự chọn số đẹp hơn.
- **Xong khi:** gate chạy trên top chuẩn và thoát 1 với `--min-wns 0` (nếu WNS còn âm); bảng và CSV có số thật; thời gian chạy ghi vào note.

#### T41. Đóng timing 2.5 ns ⚠
- **Finding:** C-5.
- **Được sửa:** `rtl/backend/ddr5_cmd_engine.sv`, `rtl/top/axi_ddr5_mc_top.sv`, `rtl/memory/ddr5_subchannel_scheduler.sv` (chỉ đường tới hạn do báo cáo chỉ ra).
- **Cần D3.** Đóng bằng RTL (pipeline đường tới hạn, giảm fan-out, chuyển quyết định), không bằng ràng buộc (R10). Mỗi vòng đo lại bằng `timing_gate.py`.
- **Xong khi:** `python tools/timing_gate.py --min-wns 0` thoát 0 trên top chuẩn, **hoặc** BLOCKED.md ghi đường tới hạn còn lại và Claude chuyển sang phương án "sửa claim" của D3. Không nới chu kỳ, không đổi part.
- **Dừng nếu:** sau 3 vòng WNS vẫn âm hoặc tụt thêm.

### LÀN 5: BACKEND VÀ TÀI LIỆU

#### T50. ZEM, chipkill: ghi giới hạn hoặc nối
- **Finding:** M-7, M-8.
- **Được sửa:** `LIMITATIONS.md`, `PEER_REVIEW_DEFENSE_DOSSIER.md` (hoặc bản trong `docs/`), `README.md` (chỉ đoạn liên quan), và `rtl/top/axi_ddr5_mc_top.sv` (chỉ khi D4 chọn nối).
- **Cần D4.** Đề xuất (nếu D4 = ghi giới hạn): ghi rõ ZEM chưa nối (`i_zem_lookup_valid=1'b0`), scrubber chỉ phát ACT/PRE qua DRM, `rs_chipkill_*` chưa instantiate, `ecc_chipkill_fallback_req` chưa dùng; sửa mô tả "ECC thử → MAC → Chipkill" cho đúng RTL; lệnh tái lập trỏ `gf256_arith_pkg.sv` (không phải `gf16_arith_pkg.sv`); RS trên GF(2^8).
- **Xong khi:** `python tools/check_documentation_consistency.py` thoát 0 (mở rộng nếu cần); không còn mô tả cơ chế vắng mặt trong RTL.

#### T51. Số liệu và tuyên bố trong tài liệu ⚠
- **Finding:** C-5, C-6, H-9, L-4.
- **Được sửa:** `README.md`, `DESIGN.md`, `EVALUATION.md`, `LIMITATIONS.md`, `REPRODUCIBILITY.md`, `GOLDEN_OUTPUTS/README.md`, `tools/check_documentation_consistency.py`.
- **Cần D3, D5.** Quy tắc R3/R14 áp dụng toàn phần.

1. Thay mọi số test/pass bằng số đọc từ `regression_summary.json` (T02), kèm commit và ngày.
2. Fmax/WNS/GE: dùng số từ `reports/remediation/timing_history.csv` (T40/T41) hoặc xóa claim; D3 quyết định; 424,1 MHz/+0,142 ns không có nguồn thì phải gỡ.
3. Bảng benchmark không nguồn: gắn nhãn "chưa tái lập" tại mọi nơi trích (D5); không xóa, không sinh số mới.
4. README "93,5%" → 93,73% (255·16/65025); gỡ "92,3% coverage" và "11 thuộc tính formal" nếu không có file nguồn (đếm thực `formal/*.sby`).
5. `check_documentation_consistency.py` phải thoát 1 khi: số test trong tài liệu ≠ `regression_summary.json`, hoặc claim Fmax không có dòng trong `timing_history.csv`.
- **Xong khi:** script trên thoát 0; `grep -rn "22468\|424.1\|0.142" README.md DESIGN.md EVALUATION.md` không còn xuất hiện ngoài mục "chưa tái lập"; không số nào gõ tay (R3).

#### T52. Logic chết và mục nhỏ
- **Finding:** L-1, L-2, L-3.
- **Được sửa:** `rtl/bus/apb_csr_regs.sv` (chỉ nối cờ), `rtl/frontend/axi_slave_frontend.sv`, `rtl/backend/ddr5_cmd_engine.sv` (tABO), `rtl/backend/directed_refresh_manager.sv`, `rtl/crypto/aes_sbox_composite.sv`.

1. Nối `cfg_parity_check_en` từ CSR; kiểm parity không phụ thuộc `wchk != 0`; chặn beat lỗi.
2. RFM ưu tiên khi ABO chờ (thêm bộ đếm tABO) nếu không tăng WNS tệ (R12); hàng ±1..3 xử lý biên (không wrap).
3. S-box LUT: ghi giới hạn side-channel vào `LIMITATIONS.md`; không đổi cấu trúc S-box trừ khi có spec riêng.
- **Xong khi:** từng mục có check hoặc ghi chú giới hạn kèm bằng chứng; không chạm logic ngoài danh sách.

### LÀN 6: MÔI TRƯỜNG VERIFICATION

#### T60. Môi trường pyuvm (AXI, APB, scoreboard) ⚠
- **Finding:** không có finding riêng; mục tiêu G3.
- **Được sửa:** `tb/uvm/**` (mới), `requirements.txt`, `run_all_tests.py`.

```text
tb/uvm/
  common/    seq_item, base_test, ghi JSON (seed, commit), gate
  agents/    axi_agent (độ trễ AW/W/B/AR/R độc lập, RREADY/BREADY ngẫu nhiên, WSTRB ngẫu nhiên), apb_agent (pprot ngẫu nhiên),
             dfi_dram_agent (dùng tb/common/dram_model.sv), fault_agent (SEU/stuck/glitch qua $deposit, ghi nhật ký)
  golden/    aes_xts_model.py (IEEE 1619), rs_secded_model.py, addr_map_model.py — viết độc lập, không import từ RTL/TB cũ
  envs/      mc_env, csr_env
  sequences/ theo ID corner case (mục 8 của findings)
  tests/ run_uvm.py   chạy N seed, thoát 1 nếu có test fail, in seed
```
1. Scoreboard so địa chỉ DFI với AXI, dữ liệu đọc với golden. Coverage bằng bộ đếm in `[COV]`, xuất JSON cho T62.
2. Seed từ dòng lệnh, ghi vào JSON; lỗi nào cũng in seed để chạy lại.
3. Không xóa TB cũ; chỉ thay khi env UVM phủ đủ và ghi vào note.
- **Xong khi:** `python tb/uvm/run_uvm.py --env mc --seeds 5` thoát 0 ở 5 seed; đổi một phép tính trong golden thì thoát 1 và in seed; JSON có coverage và commit.
- **Dừng nếu:** pyuvm không chạy với Icarus sau 3 lần: báo để chọn lại (không viết "UVM giả").

#### T61. SVA và formal SymbiYosys
- **Finding:** H-3, H-4, H-5, H-8 (phần thuộc tính).
- **Được sửa:** `formal/**`, `tb/sv_props/**` (mới).
- Concurrent SVA (`assert property`, `bind`) nằm ở luồng formal/xsim, **không** trong file Icarus biên dịch (R7). Thuộc tính tối thiểu: AXI VALID giữ tới handshake; `sec_locked |-> $stable(enc_enable)`; `!keys_valid |-> !pipe_in_valid`; `arvalid&&arready |-> ##[1:N] rvalid&&rlast`; `open_row[bg,ba]` đã ACT trước RD/WR; số beat R == số beat ROB retire; (major,minor,addr) duy nhất.
- **Chỉ thêm thuộc tính đúng với RTL hiện tại hoặc thuộc tính sẽ fail trên lỗi còn mở thì để trong `formal/known_open.txt`** (không làm regression đỏ toàn bộ).
- **Xong khi:** `sby` chạy được các thuộc tính đúng (đếm `PASS`/`FAIL` thật); `cover` đạt; không `sby` thì ghi `CHƯA CHẠY` (R4).

#### T62. Ma trận corner case, coverage, mutation
- **Finding:** không có finding riêng.
- **Được sửa:** `tb/corner_cases/matrix.yaml` (mới), `tools/check_corner_matrix.py` (mới), `tools/mutate_rtl.py` (mới), `run_all_tests.py`.
- Chuyển danh sách corner case thành `matrix.yaml` (`id`, block, mô tả, expected, test, coverpoint). `check_corner_matrix.py` thoát 1 khi ID thiếu test, số lần chạm = 0, hoặc test fail (lỗi mở có trong known_failing thì được phép). `mutate_rtl.py` đảo điều kiện/đổi toán tử/bỏ nhánh ở scheduler, ROB, adapter, CSR; báo tỉ lệ mutant bị bắt và danh sách sống sót. **Khi báo, ghi rõ phạm vi (bao nhiêu mutant, chọn thế nào); không viết "mutation score 100%" mà không nêu phạm vi.**
- **Xong khi:** chạy được và liệt kê đúng ID chưa phủ. Mục tiêu ở T70: 100% ID có test và được chạm; ≥ 90% mutant bị bắt, mutant sống sót đều được giải thích.

#### T70. Nghiệm thu cuối
- **Finding:** không có finding riêng.
- **Được sửa:** `reports/remediation/FINAL.md` (mới), `remediation_notes/INDEX.md`.
- Điều kiện: `known_failing.txt` rỗng; regression đầy đủ thoát 0 (người dùng chạy); `timing_gate.py --min-wns 0` thoát 0 hoặc claim đã sửa theo D3; `check_corner_matrix.py` thoát 0; mọi số trong tài liệu truy được về file; Claude đã review các làn.
- **Xong khi:** `FINAL.md` liệt kê từng mục tiêu G1–G4 với lệnh và output thật.

---

## 6. BẢNG PHỦ FINDING → TASK

| Finding | Task | Finding | Task |
|---|---|---|---|
| C-1 | T04, T30 | H-9 | T02, T51 |
| C-2 | T04, T31 | H-10 | T02 |
| C-3 | T04, T10 | H-11 | T01 |
| C-4 | T04, T10, T11 | H-12 | T03 |
| C-5 | T40, T41, T51 | H-13 | T05, T06 |
| C-6 | T51 | M-1 | T12 |
| H-1 | T04, T11 | M-2, M-3 | T14 |
| H-2 | T04, T12 | M-4 | T15 |
| H-3 | T04, T13, T61 | M-5 | T34 |
| H-4, H-5 | T04, T20, T61 | M-6 | T21 |
| H-6 | T04, T21 | M-7, M-8 | T50 |
| H-7 | T04, T32 | M-9 | T01 |
| H-8 | T04, T33, T61 | M-10 | T62 (bench_trace ngưỡng, `tb_rs_chipkill` check) |
| L-1, L-2, L-3 | T52, T15 | M-11 | T03 |
| L-4 | T51 | | |

---

## 7. FILE NOTE CHO LƯỢT REVIEW CỦA CLAUDE

### 7.1. Mẫu `remediation_notes/<Txx>.md`

Ghi `base_commit` (`git rev-parse HEAD`) **trước khi bắt đầu sửa**. Note được commit cùng task nên không chứa hash của chính commit đó; người review tìm commit qua `fix(<Txx>)` trong `git log`.

```markdown
# <Txx>: <tên task>
- base_commit: <hash>
- trạng thái: XONG | DỪNG (lý do)
- quyết định đã dùng: D1=..., D3=... (hoặc "không có")

## Finding
| ID | Kết quả | Ghi chú |
|---|---|---|
| H-2 | ĐÃ SỬA / SỬA MỘT PHẦN / KHÔNG SỬA | lý do nếu không sửa đủ |

## Chỗ đã sửa
| File | Vị trí sau khi sửa (dòng + tên tín hiệu/hàm) | Finding | Thay đổi | Lý do |
|---|---|---|---|---|
| rtl/memory/ddr5_subchannel_scheduler.sv:160 | bank_state | H-2 | Index theo {bg,bank} | BG bị bỏ khỏi chỉ mục |

## Test đã đổi hoặc xóa (quy tắc R2)
Test nào, hành vi cũ sai ra sao, finding nào. Không có thì ghi "không có".

## Kết quả kiểm chứng
| Tiêu chí trong plan | Lệnh | Kết quả thật | Log |
|---|---|---|---|

## Timing (quy tắc R12)
WNS, LUT, FF trước và sau task. Task không sửa RTL thì ghi "không sửa RTL".

## Bất biến tính mới (quy tắc R13)
Check đang đạt vẫn đạt (so `baseline_failures.txt`). Task không đụng thì ghi "không liên quan".

## Corner case
ID đã thêm hoặc chuyển sang pass. Không có thì ghi "không có".

## Ngoài phạm vi "Được sửa" (quy tắc R5)
File nào, vì sao. Không có thì ghi "không có".

## Reviewer nên soi kỹ
Tối đa 5 chỗ ít chắc nhất, trường hợp chưa test, giả định chưa kiểm chứng.

## Chưa làm / nợ lại
Việc gì, ai cần làm tiếp. Không có thì ghi "không có".
```

**Quy định khi điền:** số dòng là số dòng **sau khi sửa**, mỗi đoạn đổi logic một dòng; không ghi "đã kiểm tra" nếu không có lệnh và log (`CHƯA CHẠY` theo R4); mục "Reviewer nên soi kỹ" không được trống ở task ⚠.

### 7.2. Chỉ mục và công cụ kiểm tra

- `remediation_notes/INDEX.md`: một dòng mỗi task: `| Task | Trạng thái | Base Commit | Finding | Còn nợ | Ghi chú |`. Gemini cập nhật khi xong.
- `remediation_notes/REVIEW_LOG.md`: do Claude ghi, mỗi dòng một quyết định có hiệu lực cho các task sau.
- `python tools/check_notes.py <Txx>` hoặc `--all`: kiểm đủ mục, finding trong brief có mặt trong bảng, mọi file đổi từ `base_commit` được nhắc, đường dẫn trong "Chỗ đã sửa" tồn tại.
- `python tools/safety_check.py --task <Txx>`: kiểm bảo vệ R9, git, và **mọi file trong commit của task nằm trong "Được sửa"** (cộng `remediation_notes/`, `reports/remediation/`, `build/review/`).
- Task có dòng `- trạng thái: DỪNG` không được đánh dấu xong; `check_notes.py` thoát 1.

### 7.3. Cách nhờ Claude review

Sau mỗi task hoặc cuối làn: gửi Claude `remediation_notes/<Txx>.md` và `build/review/<Txx>/`. Claude đọc 4 file của gói, mở đúng `file:dòng` trong `locations.txt`, chạy lại độc lập `tools/run_one_tb.py` / `tb/findings/run_findings.py`, so `git diff rem/<Txx-1> rem/<Txx>` tìm assert bị xóa, ngưỡng bị nới, hằng số lạ, XFAIL mới. Quyết định ghi vào `REVIEW_LOG.md`.

### 7.4. Gói review đúng vị trí sửa (R16)

Cuối mỗi task, Gemini tạo `build/review/<Txx>/` (đã gitignore) gồm đúng bốn file; trong báo cáo chỉ trỏ đường dẫn, không dán nội dung dài:
1. `diff.patch`: `git diff -U3 <base_commit>..HEAD -- <file trong Được sửa>` kèm `git diff --stat` ở đầu.
2. `locations.txt`: mỗi dòng `file:dòng_đầu-dòng_cuối | lý do 1 câu | ID finding`.
3. `before_after.log`: lọc log đúng chỗ, không dán cả log: `grep -h "TB_RESULT\|^\[FAIL\]\|ERR" build/one_<top>/sim.log | head -20` cho lần chạy TRƯỚC (fail tái hiện) và SAU sửa.
4. `scope_check.txt`: `git status --short` trước/sau và kết quả `python tools/safety_check.py --task <Txx>`.

---

## 8. PHƯƠNG PHÁP VERIFICATION (chuẩn doanh nghiệp)

**Tầng A, chạy được ngay (Icarus, cocotb/pyuvm, SymbiYosys):** check tái hiện theo finding (T04); pyuvm với agent AXI/APB/DFI, scoreboard so mô hình tham chiếu Python độc lập, coverage dạng bộ đếm (T60); SVA + formal BMC/k-induction cho bất biến (T61); directed fault-injection (`$deposit` ở negedge); monitor tái dùng `qs_axi_txn_chk`, `qs_engine_port_chk`, `dfi_jedec_checker` gắn vào mọi TB top.

**Tầng B, cần công cụ thương mại hoặc mở rộng (ghi vào lộ trình, không bắt buộc vòng này):** UVM 1.2 trên Questa/VCS/Xcelium với RAL cho CSR và covergroup cross (burst × size × BG × bank × profile bảo mật); formal sign-off (JasperGold/VC Formal); CDC/RDC lint (SpyGlass/Questa CDC) cho reset miền và `clk_ddr`; mô phỏng gate-level sau synth; mutation testing.

**Tiêu chí đóng (sign-off):** (1) regression đầy đủ không XFAIL ẩn, số liệu có commit/ngày; (2) mọi Critical/High có check fail trước, pass sau; (3) bất biến SVA được chứng minh bằng formal hoặc `cover` đạt; (4) coverage chức năng và ma trận corner case ghi báo cáo, mutation nêu phạm vi; (5) WNS ≥ 0 ở 2.5 ns bằng synth thật hoặc claim đã sửa; (6) tài liệu chỉ chứa số truy được về file trong repo.
