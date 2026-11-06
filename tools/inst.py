p = r'D:\RAM\rtl\top\bank_credit_ctrl.sv'
s = open(p, 'rb').read()
idx = s.find(b'bk_cnt[b] <= bk_base[b];')
end = s.find(b'for (int g = 0; g < BG_COUNT; g++)', idx)
s = s[:idx] + b'for (int b = 0; b < NBK; b++) begin\r\n                bk_cnt[b] <= bk_base[b];\r\n                if (b == 17 && (add_v || sub_v)) begin\r\n                    $display("[DBG_BK17] t=%0t add=%0d sub=%0d cnt=%0d->%0d rel_bg=%0d rel_bk=%0d", $time, add_v, sub_v, bk_cnt[b], bk_base[b], i_rel_bg, i_rel_bank);\r\n                end\r\n            end\r\n            ' + s[end:]
open(p, 'wb').write(s)
print("done")
