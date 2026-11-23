# Third-Party Attribution & Overlay Notice (`sim/ramulator2_qshield/NOTICE.md`)
Chức năng: Ghi nguồn giấy phép MIT của các tệp sao chép và điều chỉnh từ Ramulator2 upstream `72427a1`.

- **Upstream repository:** `CMU-SAFARI/ramulator2` (bản cục bộ `~/ramulator2`), commit `72427a1bba3771564c4fb0e494ba02242fd1eaa7`.
- **Giấy phép upstream:** MIT License (cho phép sao chép, sửa đổi và tích hợp trong overlay kèm giữ ghi nhận nguồn).
- **Các tệp điều chỉnh từ upstream `72427a1` trong thư mục này:**
  1. `src/ramulator/controller/refresh/impl/all_bank.cpp`: bổ sung `{"DDR4_VRR", "Rank"}` và `{"DDR5_VRR", "Rank"}` vào bảng `all_bank_refresh_scopes` (T80).
  2. `src/ramulator/controller/plugin/impl/para_act.cpp`: dẫn xuất từ `para.cpp` (`72427a1`), thay lệnh không chuẩn `VRR` bằng chuỗi `ACT -> PREpb` chuẩn JEDEC cho các hàng nạn nhân `row ± 1, row ± 2` trên DRAM thương mại (T87).
  3. `src/ramulator/controller/plugin/impl/graphene_act.cpp`: dẫn xuất từ `graphene.cpp` (`72427a1`), giữ nguyên thuật toán Misra-Gries / spillover và thay `VRR` bằng chuỗi `ACT -> PREpb` chuẩn JEDEC cho bán kính 2 (T87).
  4. `src/ramulator/controller/plugin/impl/hydra_act.cpp`: dẫn xuất từ `hydra.cpp` (`72427a1`), giữ nguyên cấu trúc GCT/RCC/RCT/RCTCT và thay `VRR` bằng chuỗi `ACT -> PREpb` chuẩn JEDEC cho bán kính 2 (T87).
- **Ràng buộc tài liệu tham khảo không giấy phép:** `~/refs/Chronus` và `~/refs/BlockHammer` chỉ dùng để đọc tham khảo; tuyệt đối không sao chép mã nguồn vào kho này. Trace đánh giá Chronus (Zenodo DOI `10.5281/zenodo.14281771`, CC-BY-4.0) chỉ được đọc tại chỗ ngoài repo.
