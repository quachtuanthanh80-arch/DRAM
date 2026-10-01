# test_channel_natural_sequence.py
# Verification of all AXI channels and DDR5 subchannels using continuous natural number sequences

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset_dut(dut):
    dut.aresetn_axi.value = 0
    dut.aresetn_ddr.value = 0

    dut.s_axi_awid.value    = 0
    dut.s_axi_awaddr.value  = 0
    dut.s_axi_awlen.value   = 0
    dut.s_axi_awsize.value  = 3
    dut.s_axi_awburst.value = 1
    dut.s_axi_awqos.value   = 0
    dut.s_axi_awvalid.value = 0

    dut.s_axi_wdata.value   = 0
    dut.s_axi_wstrb.value   = 0
    dut.s_axi_wlast.value   = 0
    dut.s_axi_wvalid.value  = 0

    dut.s_axi_bready.value  = 1

    dut.s_axi_arid.value    = 0
    dut.s_axi_araddr.value  = 0
    dut.s_axi_arlen.value   = 0
    dut.s_axi_arsize.value  = 3
    dut.s_axi_arburst.value = 1
    dut.s_axi_arqos.value   = 0
    dut.s_axi_arvalid.value = 0

    dut.s_axi_rready.value  = 1

    dut.cfg_is_ddr5.value      = 1
    dut.cfg_dual_hash_en.value = 1
    dut.cfg_rh_threshold.value = 64
    dut.cfg_window_size.value  = 200

    for _ in range(10):
        await RisingEdge(dut.clk_axi)

    dut.aresetn_axi.value = 1
    dut.aresetn_ddr.value = 1

    for _ in range(5):
        await RisingEdge(dut.clk_axi)

@cocotb.test()
async def test_axi_write_channels_natural_sequence(dut):
    """Kiem tra truyen chuoi so tu nhien lien tuc tren cac channel ghi AXI4 (AW -> W -> B)"""
    clock_axi = Clock(dut.clk_axi, 5.0, unit="ns")
    clock_ddr = Clock(dut.clk_ddr, 5.0, unit="ns")
    cocotb.start_soon(clock_axi.start())
    cocotb.start_soon(clock_ddr.start())

    await reset_dut(dut)

    num_transactions = 16
    b_received_ids = []

    # Tien trinh theo doi kenh phan hoi B channel
    async def b_channel_monitor():
        while len(b_received_ids) < num_transactions:
            await RisingEdge(dut.clk_axi)
            if int(dut.s_axi_bvalid.value) == 1 and int(dut.s_axi_bready.value) == 1:
                bid = int(dut.s_axi_bid.value)
                bresp = int(dut.s_axi_bresp.value)
                b_received_ids.append(bid)
                dut._log.info(f"B Channel: Nhan phan hoi BRESP={bresp} cho Transaction ID={bid}")
                assert bresp == 0, f"Bresp phai la OKAY (0), nhan duoc {bresp}"

    cocotb.start_soon(b_channel_monitor())

    # Phat 16 giao dich ghi voi so tu nhien lien tuc tu 0 den 15
    for n in range(num_transactions):
        natural_num = n
        natural_addr = natural_num * 64
        natural_data = 0xCAFE_0000_0000_0000 | natural_num

        dut.s_axi_awid.value    = natural_num & 0xF
        dut.s_axi_awaddr.value  = natural_addr
        dut.s_axi_awlen.value   = 0
        dut.s_axi_awsize.value  = 3
        dut.s_axi_awburst.value = 1
        dut.s_axi_awqos.value   = natural_num % 8
        dut.s_axi_awvalid.value = 1

        dut.s_axi_wdata.value   = natural_data
        dut.s_axi_wstrb.value   = 0xFF
        dut.s_axi_wlast.value   = 1
        dut.s_axi_wvalid.value  = 1

        aw_done = False
        w_done  = False

        for _ in range(40):
            await RisingEdge(dut.clk_axi)
            if int(dut.s_axi_awready.value) == 1 and not aw_done:
                aw_done = True
                dut.s_axi_awvalid.value = 0
            if int(dut.s_axi_wready.value) == 1 and not w_done:
                w_done = True
                dut.s_axi_wvalid.value = 0
            if aw_done and w_done:
                break

        assert aw_done, f"Handshake AW bi timeout tai so tu nhien N={natural_num}"
        assert w_done,  f"Handshake W bi timeout tai so tu nhien N={natural_num}"

    # Cho tat ca cac giao dich B channel hoan tat
    for _ in range(200):
        await RisingEdge(dut.clk_axi)
        if len(b_received_ids) == num_transactions:
            break

    assert len(b_received_ids) == num_transactions, \
        f"Kenh B chi nhan {len(b_received_ids)}/{num_transactions} giao dich"
    dut._log.info(f"Kenh ghi hoan tat thanh cong 16/16 so tu nhien: {b_received_ids}")

@cocotb.test()
async def test_axi_read_channels_natural_sequence(dut):
    """Kiem tra truyen chuoi so tu nhien lien tuc tren cac channel doc AXI4 (AR -> R)"""
    clock_axi = Clock(dut.clk_axi, 5.0, unit="ns")
    clock_ddr = Clock(dut.clk_ddr, 5.0, unit="ns")
    cocotb.start_soon(clock_axi.start())
    cocotb.start_soon(clock_ddr.start())

    await reset_dut(dut)

    num_reads = 8
    r_received_ids = []

    # Monitor R channel
    async def r_channel_monitor():
        while len(r_received_ids) < num_reads:
            await RisingEdge(dut.clk_axi)
            if int(dut.s_axi_rvalid.value) == 1 and int(dut.s_axi_rready.value) == 1:
                rid = int(dut.s_axi_rid.value)
                rdata = int(dut.s_axi_rdata.value)
                r_received_ids.append(rid)
                dut._log.info(f"R Channel: Nhan Data=0x{rdata:016x} cho Read ID={rid}")

    cocotb.start_soon(r_channel_monitor())

    for n in range(num_reads):
        dut.s_axi_arid.value    = n & 0xF
        dut.s_axi_araddr.value  = 0x0002_0000 + (n * 64)
        dut.s_axi_arlen.value   = 0
        dut.s_axi_arsize.value  = 3
        dut.s_axi_arburst.value = 1
        dut.s_axi_arqos.value   = 4
        dut.s_axi_arvalid.value = 1

        ar_done = False
        for _ in range(40):
            await RisingEdge(dut.clk_axi)
            if int(dut.s_axi_arready.value) == 1:
                ar_done = True
                dut.s_axi_arvalid.value = 0
                break

        assert ar_done, f"Handshake AR bi timeout tai so tu nhien N={n}"

    for _ in range(250):
        await RisingEdge(dut.clk_axi)
        if len(r_received_ids) == num_reads:
            break

    assert len(r_received_ids) == num_reads, \
        f"Kenh doc R chi nhan {len(r_received_ids)}/{num_reads} giao dich"
    dut._log.info(f"Kenh doc hoan tat thanh cong {len(r_received_ids)}/{num_reads} so tu nhien: {r_received_ids}")

@cocotb.test()
async def test_ddr5_channel_bankgroup_natural_interleaving(dut):
    """Kiem tra su phan bo cac so tu nhien lien tuc N=0..7 vao cac Bank Group DDR5"""
    clock_axi = Clock(dut.clk_axi, 5.0, unit="ns")
    clock_ddr = Clock(dut.clk_ddr, 5.0, unit="ns")
    cocotb.start_soon(clock_axi.start())
    cocotb.start_soon(clock_ddr.start())

    await reset_dut(dut)

    bg_mapping = {}

    for n in range(8):
        natural_addr = n * 64

        dut.s_axi_awid.value    = n
        dut.s_axi_awaddr.value  = natural_addr
        dut.s_axi_awlen.value   = 0
        dut.s_axi_awsize.value  = 3
        dut.s_axi_awburst.value = 1
        dut.s_axi_awqos.value   = 0
        dut.s_axi_awvalid.value = 1

        dut.s_axi_wdata.value   = 0x1000 + n
        dut.s_axi_wstrb.value   = 0xFF
        dut.s_axi_wlast.value   = 1
        dut.s_axi_wvalid.value  = 1

        for _ in range(30):
            await RisingEdge(dut.clk_axi)
            if int(dut.s_axi_awready.value) == 1:
                dut.s_axi_awvalid.value = 0
            if int(dut.s_axi_wready.value) == 1:
                dut.s_axi_wvalid.value = 0
            if not dut.s_axi_awvalid.value and not dut.s_axi_wvalid.value:
                break

        # Theo doi command tren DFI bus
        for _ in range(30):
            await RisingEdge(dut.clk_axi)
            cmd = int(dut.dfi_cmd.value)
            if cmd != 0:
                bg = int(dut.dfi_bg.value)
                bank = int(dut.dfi_bank.value)
                bg_mapping[n] = (bg, bank)
                dut._log.info(f"So tu nhien N={n} (Addr={hex(natural_addr)}) -> DFI Cmd={cmd}, BG={bg}, Bank={bank}")
                break

    dut._log.info(f"Bang phan bo Bank Group theo chuoi so tu nhien: {bg_mapping}")
    assert len(bg_mapping) > 0, "Khong bat duoc lenh DFI nao cho chuoi so tu nhien"
