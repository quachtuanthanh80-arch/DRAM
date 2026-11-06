// File:      qs_hier.svh
// Chức năng: Gom mọi tên tín hiệu nội bộ (probe/bơm lỗi) mà testbench tham chiếu theo phân cấp vào một chỗ để đổi tên khi RTL v2 chốt tên.

// Chỉ dùng các tên spec_v2 nêu đích danh (verification_plan §1.3). Đối số là đường dẫn instance, ví dụ
// `QS_E_REF_MODE(dut.u_cmd_engine) hoặc `QS_E_REF_MODE(u_dut). Không dùng probe để suy ra kỳ vọng.
`ifndef QS_HIER_SVH
`define QS_HIER_SVH

`define QS_STR(p) `"p`"

// Instance con trong top (spec_v2 §4)
`define QS_TOP_ENG(t)            t.u_cmd_engine
`define QS_TOP_DRM(t)            t.u_drm
`define QS_TOP_IQ(t)             t.u_rd_iq
`define QS_TOP_MAP(t)            t.u_addr_mapper

// Engine: có ở cả v1 và v2
`define QS_E_REF_MODE(e)         e.ref_mode
`define QS_E_REF_OWED(e)         e.ref_owed
`define QS_E_LAST_ACT(e)         e.last_act
`define QS_E_LAST_WR(e)          e.last_wr
`define QS_E_RAA_CNT(e)          e.rolling_act_cnt
`define QS_E_RAA_INV(e)          e.rolling_act_inv
`define QS_E_S_V(e)              e.s_v
`define QS_E_RFC_Z(e)            e.rfc_z
`define QS_E_RCD_Z(e)            e.rcd_z
`define QS_E_RP_Z(e)             e.rp_z
`define QS_E_RAS_Z(e)            e.ras_z
`define QS_E_CCD_Z(e)            e.ccd_z
`define QS_E_CCD_S_Z(e)          e.ccd_s_z
`define QS_E_RRD_S_Z(e)          e.rrd_s_z
`define QS_E_RRD_L_Z(e)          e.rrd_l_z
`define QS_E_WTR_S_Z(e)          e.wtr_s_z
`define QS_E_WTR_L_Z(e)          e.wtr_l_z
`define QS_E_DQ_WR_OK(e)         e.dq_wr_ok
`define QS_E_DQ_RD_OK(e)         e.dq_rd_ok

// Engine: chỉ có ở v2 (M-01, M-03, M-04, M-05)
`define QS_E_USER_BLK(e)         e.user_blk_q
`define QS_E_USER_BLK_Q(e)       e.user_blk_q
`define QS_E_LAT_KIND(e)         e.lat_kind
`define QS_E_REF_WD_CNT(e)       e.ref_wd_cnt
`define QS_E_REF_WD_EXP(e)       e.ref_wd_exp
`define QS_E_RFC_Z2(e)           e.rfc_z2
`define QS_E_CCDW_Z(e)           e.ccdw_z
`define QS_E_RD_ST(e)            e.rd_st
`define QS_E_EXP_V(e)            e.exp_v
`define QS_E_RD_PEND(e)          (e.rt_wr - e.rt_rd)

// DRM
`define QS_D_INJ_STATE_V1(d)     d.inj_state
`define QS_D_INJ_OH(d)           d.inj_oh
`define QS_D_BLKP_A(d)           d.blkp_a
`define QS_D_BLKP_B(d)           d.blkp_b
`define QS_D_PQ_V(d)             d.pq_v
`define QS_D_PQ_REG(d)           d.pq_region
`define QS_D_QUEUE_EMPTY(d)      d.queue_empty
`define QS_D_AF_EMPTY(d)         d.af_empty

// Top: có ở cả v1 và v2
`ifdef QS_BASELINE_V1
`define QS_T_BK_CNT(t)           t.bk_cnt
`define QS_T_BANK_CREDIT(t)      t.bank_credit
`define QS_T_WBANK_CREDIT(t)     t.wbank_credit
`else
`define QS_T_BK_CNT(t)           t.u_bank_credit.bk_cnt
`define QS_T_BANK_CREDIT(t)      t.u_bank_credit.bank_credit
`define QS_T_WBANK_CREDIT(t)     t.u_bank_credit.wbank_credit
`endif
`define QS_T_SDC_CMD_READY(t)    t.sdc_cmd_ready
`define QS_T_CS_VALID(t)         t.cs_valid
`define QS_T_CS_IS_MIT(t)        t.cs_is_mitigation
`define QS_T_CS_BG(t)            t.cs_bg
`define QS_T_RDQ_VALID(t)        t.rdq_valid
`define QS_T_KF_RD(t)            t.kf_rd
`define QS_T_KF_WR(t)            t.kf_wr
`define QS_T_RA_RD(t)            t.ra_rd
`define QS_T_RA_WR(t)            t.ra_wr

// Top: chỉ có ở v2 (M-02, M-05, M-08)
`define QS_T_Q_IN_VALID(t)       t.q_in_valid
`define QS_T_MAP_CFG_Q(t)        t.map_cfg_q
`define QS_T_CFG_PEND_Q(t)       t.cfg_pend_q
`define QS_T_MAP_IDLE_Q(t)       t.map_idle_q
`define QS_T_WR_BLK_CFG_Q(t)     t.wr_blk_cfg_q
`define QS_T_FAULT_STICKY(t)     t.fault_sticky
`define QS_T_FAULT_ST(t)         t.fault_sticky
`define QS_T_ROB_USED(t)         t.rob_used

// Mã trạng thái theo spec_v2 §5 (TB tự gõ, không lấy localparam của DUT)
`define QS_RS_SYNC               2'b01
`define QS_RS_FLUSH              2'b10
`define QS_K_REF                 2'b01
`define QS_K_RFM                 2'b10
`define QS_S_IDLE                7'b0000001
`define QS_S_P1R                 7'b0000010

`endif
