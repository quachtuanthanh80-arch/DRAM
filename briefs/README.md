# Danh sách brief theo task

## Cách dùng (đọc trước khi giao việc)

- Mỗi phiên chỉ kéo MỘT file brief vào chat, không kéo nhiều file, không kéo cả thư mục
- Trước phiên Gemini đầu tiên: làm T00 (người dùng tự chạy) và `python tools/safety_check.py --init`
- Làm tuần tự theo "Thứ tự chạy"; chỉ mở task kế tiếp khi task trước xong và `python tools/safety_check.py --task <Txx>` thoát 0
- Task ở trạng thái KHÓA phụ thuộc quyết định chưa chốt (GEMINI_EXECUTION_PLAN.md mục 3): không giao cho tới khi người dùng chốt
- Mỗi task một commit trên nhánh `remediation/main`; cuối mỗi làn dừng để Claude review
- Mức suy luận gợi ý: High cho task ⚠, Medium cho phần còn lại; task ⚠ nên để Claude xem kế hoạch trước khi chạy
- Sinh lại brief khi plan đổi: `python tools/make_briefs.py`

## Thứ tự chạy

T00 → T01 → T02 → T03 → T04 → T05 → T06 → T10 → T11 → T12 → T13 → T14 → T15 → T20 → T21 → T40 → T30 → T31 → T32 → T33 → T34 → T41 → T50 → T52 → T60 → T61 → T62 → T51 → T70

## Bảng task

| Task | Tên | Phụ thuộc | Quyết định | Mức gợi ý | Trạng thái | Cỡ brief |
|---|---|---|---|---|---|---|
| [T00](T00.md) | Snapshot, nhánh, tag (người dùng tự chạy, Gemini không làm) | — | D6 ✔ | Medium | Sẵn sàng | 14 KB |
| [T01](T01.md) | Runner và đếm check trung thực | T00 | D6 | Medium | Sẵn sàng | 14 KB |
| [T02](T02.md) | Hợp nhất kết quả regression, baseline | T01 | — | Medium | Sẵn sàng | 14 KB |
| [T03](T03.md) | Golden verify thật, tham chiếu gãy | T01 | — | Medium | Sẵn sàng | 14 KB |
| [T04](T04.md) | Bộ check tái hiện finding `tb/findings` ⚠ | T02 | — | High | Sẵn sàng | 17 KB |
| [T05](T05.md) | Sửa TB rt02, rt03 (H-13, phần TB) | T02 | — | Medium | Sẵn sàng | 13 KB |
| [T06](T06.md) | Read starvation của ddr5_cmd_engine (tb_rt01) ⚠ | T05 | — | High | Sẵn sàng | 13 KB |
| [T10](T10.md) | Phạm vi top chuẩn, nhãn top demo | T04 | D1 ✔ | Medium | Sẵn sàng | 15 KB |
| [T11](T11.md) | Rà soát đường chính `axi_ddr5_mc_top` theo lớp lỗi của top demo ⚠ | T10 | D1 ✔ | High | Sẵn sàng | 15 KB |
| [T12](T12.md) | Scheduler index {bg,bank} và tRAS/tWR/tFAW ⚠ | T04 | — | High | Sẵn sàng | 13 KB |
| [T13](T13.md) | RREADY của R channel | T04 | — | Medium | Sẵn sàng | 13 KB |
| [T14](T14.md) | WSTRB, bytes_total 4KB | T04 | — | Medium | Sẵn sàng | 13 KB |
| [T15](T15.md) | Thống nhất miền clock/top | T10 | D1 ✔ | Medium | Sẵn sàng | 13 KB |
| [T20](T20.md) | Khóa enc_enable, pprot, keys_valid | T04 | — | Medium | Sẵn sàng | 13 KB |
| [T21](T21.md) | Seed, ngưỡng, đọc ngược khóa, TMR sec_locked | T20 | — | Medium | Sẵn sàng | 13 KB |
| [T40](T40.md) | Timing gate | T04 | D3 | Medium | KHÓA (D3) | 13 KB |
| [T30](T30.md) | Nối crypto vào `axi_ddr5_mc_top`, InvCipher ⚠ | T11, T20 | D1 ✔, D2 | High | KHÓA (D2) | 15 KB |
| [T31](T31.md) | Tweak XTS đúng chuẩn IEEE 1619 ⚠ | T30 | D2 | High | KHÓA (D2) | 13 KB |
| [T32](T32.md) | Scrambler có version | T30 | D2 | Medium | KHÓA (D2) | 13 KB |
| [T33](T33.md) | Split counter ⚠ | T30 | D2 | High | KHÓA (D2) | 13 KB |
| [T34](T34.md) | MAC phủ đủ địa chỉ/bộ đếm | T31, T33 | D2 | Medium | KHÓA (D2) | 13 KB |
| [T41](T41.md) | Đóng timing 2.5 ns ⚠ | T40, Làn 1–3 | D3 | High | KHÓA (D3) | 13 KB |
| [T50](T50.md) | ZEM, chipkill: ghi giới hạn hoặc nối | T04 | D4 | Medium | KHÓA (D4) | 13 KB |
| [T52](T52.md) | Logic chết và mục nhỏ | T04 | — | Medium | Sẵn sàng | 13 KB |
| [T60](T60.md) | Môi trường pyuvm (AXI, APB, scoreboard) ⚠ | T04 | — | High | Sẵn sàng | 13 KB |
| [T61](T61.md) | SVA và formal SymbiYosys | T04 | — | Medium | Sẵn sàng | 14 KB |
| [T62](T62.md) | Ma trận corner case, coverage, mutation | T60, T61 | — | Medium | Sẵn sàng | 13 KB |
| [T51](T51.md) | Số liệu và tuyên bố trong tài liệu ⚠ | T02, T40 | D3, D5 | High | KHÓA (D3, D5) | 15 KB |
| [T70](T70.md) | Nghiệm thu cuối | tất cả | — | Medium | Sẵn sàng | 12 KB |
