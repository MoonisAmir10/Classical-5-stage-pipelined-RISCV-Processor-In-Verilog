import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer


async def tap_step(dut, tms_val: int, tdi_val: int) -> None:
    await FallingEdge(dut.tck)
    dut.tms.value = tms_val
    dut.tdi.value = tdi_val
    await RisingEdge(dut.tck)
    await Timer(1, unit="ns")


async def tap_soft_reset(dut) -> None:
    for _ in range(5):
        await tap_step(dut, 1, 0)
    await tap_step(dut, 0, 0)  # -> RTI


async def jtag_shift_ir(dut, opcode: int) -> int:
    cap = 0
    await tap_step(dut, 1, 0)  # -> SEL_DR
    await tap_step(dut, 1, 0)  # -> SEL_IR
    await tap_step(dut, 0, 0)  # -> CAP_IR
    await tap_step(dut, 0, 0)  # -> SHF_IR
    for i in range(4):
        await FallingEdge(dut.tck)
        dut.tdi.value = (opcode >> i) & 1
        dut.tms.value = 1 if i == 3 else 0
        await Timer(1, unit="ns")
        assert int(dut.tdo_en.value) == 1, "TDO_EN must be high in SHF_IR"
        await RisingEdge(dut.tck)
        cap |= (int(dut.tdo.value) & 1) << i
        await Timer(1, unit="ns")
    await tap_step(dut, 1, 0)  # -> UPD_IR
    await tap_step(dut, 0, 0)  # -> RTI
    return cap


async def jtag_shift_dr(dut, length: int, din: int) -> int:
    dout = 0
    await tap_step(dut, 1, 0)  # -> SEL_DR
    await tap_step(dut, 0, 0)  # -> CAP_DR
    await tap_step(dut, 0, 0)  # -> SHF_DR
    for i in range(length):
        await FallingEdge(dut.tck)
        dut.tdi.value = (din >> i) & 1
        dut.tms.value = 1 if i == (length - 1) else 0
        await Timer(1, unit="ns")
        assert int(dut.tdo_en.value) == 1, f"TDO_EN must be high in SHF_DR bit {i}"
        await RisingEdge(dut.tck)
        dout |= (int(dut.tdo.value) & 1) << i
        await Timer(1, unit="ns")
    await tap_step(dut, 1, 0)  # -> UPD_DR
    await tap_step(dut, 0, 0)  # -> RTI
    return dout


async def init_dut(dut):
    cocotb.start_soon(Clock(dut.sys_clk, 10, unit="ns").start())
    cocotb.start_soon(Clock(dut.tck, 100, unit="ns").start())
    dut.sys_rst_n.value = 0
    dut.trst_n.value = 0
    dut.tms.value = 1
    dut.tdi.value = 0
    dut.test_mode.value = 0
    dut.scan_en.value = 0
    dut.scan_in.value = 0
    dut.prog_sel.value = 0
    dut.cache_cpu_wdata.value = 0
    dut.cache_addr_cpu.value = 0
    dut.cache_rd_cpu.value = 0
    dut.cache_wr_cpu.value = 0
    dut.cache_mem_rdata.value = 0
    dut.cache_ready_mem.value = 1
    dut.inj_en.value = 0
    dut.inj_bank.value = 0
    dut.inj_addr.value = 0
    dut.inj_bit.value = 0
    dut.inj_type.value = 0

    for _ in range(4):
        await RisingEdge(dut.sys_clk)
    await FallingEdge(dut.sys_clk)
    dut.sys_rst_n.value = 1
    await FallingEdge(dut.tck)
    dut.trst_n.value = 1
    await tap_step(dut, 0, 0)  # -> RTI


@cocotb.test()
async def test_jtag_constrained_random_scoreboard(dut):
    """JTAG-01/02/03: Directed + 40 constrained-random TDR transactions, resets & illegal opcodes."""
    await init_dut(dut)
    rng = random.Random(20261116)

    # Default IDCODE check
    idcode = await jtag_shift_dr(dut, 32, 0)
    assert idcode == 0x1BAD_D071, f"IDCODE mismatch: {idcode:#x}"

    # Scoreboard shadow models
    exp_dft_ctrl = 0x08
    exp_comp_cfg = 0x0000

    for step in range(40):
        choice = rng.choice(["dft_ctrl", "comp_cfg", "idcode", "illegal_bypass", "soft_rst", "async_trst"])
        if choice == "dft_ctrl":
            cap_ir = await jtag_shift_ir(dut, 0x4)
            assert cap_ir == 0x1, f"CAP_IR mismatch: {cap_ir:#x}"
            val = rng.randint(0, 15) | 0x08  # keep rst_mask_en safe
            rd = await jtag_shift_dr(dut, 8, val)
            assert rd == exp_dft_ctrl, f"Step {step} DFT_CTRL prior mismatch: {rd:#x} != {exp_dft_ctrl:#x}"
            exp_dft_ctrl = val
        elif choice == "comp_cfg":
            await jtag_shift_ir(dut, 0x7)
            val = (rng.randint(0, 0xFF) << 3) | rng.randint(0, 3)
            rd = await jtag_shift_dr(dut, 16, val)
            assert rd == exp_comp_cfg, f"Step {step} COMP_CFG prior mismatch: {rd:#x} != {exp_comp_cfg:#x}"
            exp_comp_cfg = val
        elif choice == "idcode":
            await jtag_shift_ir(dut, 0x1)
            assert (await jtag_shift_dr(dut, 32, 0)) == 0x1BAD_D071
        elif choice == "illegal_bypass":
            await jtag_shift_ir(dut, rng.choice([0x9, 0xA, 0xC, 0xD, 0xE, 0xF]))
            pat = rng.randint(0, 0x7F)
            rd = await jtag_shift_dr(dut, 8, pat)
            assert rd == ((pat << 1) & 0xFF), f"BYPASS 1-cycle shift mismatch: {rd:#x}"
        elif choice == "soft_rst":
            await tap_soft_reset(dut)
            exp_dft_ctrl = 0x08
            exp_comp_cfg = 0x0000
            assert int(dut.ir_reg.value) == 0x1
        else:
            # Mid-shift TRST_N abort recovery
            await tap_step(dut, 1, 0)
            await tap_step(dut, 0, 0)
            await tap_step(dut, 0, 0)  # in SHF_DR
            await FallingEdge(dut.tck)
            dut.trst_n.value = 0
            await RisingEdge(dut.tck)
            await FallingEdge(dut.tck)
            dut.trst_n.value = 1
            await tap_step(dut, 0, 0)  # -> RTI
            exp_dft_ctrl = 0x08
            exp_comp_cfg = 0x0000


@cocotb.test()
async def test_mbist_fault_injection_matrix_via_jtag(dut):
    """MBIST-01/02: Clean March-C + Checkerboard + full bank/addr/bit/type fault matrix via JTAG."""
    await init_dut(dut)
    dut.test_mode.value = 1

    # 1. Clean March-C (all 4 banks)
    await jtag_shift_ir(dut, 0x5)  # MBIST_CMD
    await jtag_shift_dr(dut, 8, 0x1F)
    for _ in range(250):
        await RisingEdge(dut.tck)
        if int(dut.bist_done.value) == 1:
            break
    assert int(dut.bist_done.value) == 1 and int(dut.bist_fail.value) == 0

    # 2. Clean Checkerboard March
    await jtag_shift_dr(dut, 8, 0x5F)
    await Timer(500, unit="ns")
    for _ in range(250):
        await RisingEdge(dut.tck)
        if int(dut.bist_done.value) == 1:
            break
    assert int(dut.bist_done.value) == 1 and int(dut.bist_fail.value) == 0

    # 3. Sweep all 4 banks x 3 fault types (SA0, SA1, flip) at randomized addresses & bits
    rng = random.Random(42)
    for bank in range(4):
        max_bit = 13 if bank < 2 else 31
        for ftype in (1, 2, 3):  # 1=SA0, 2=SA1, 3=flip
            addr = rng.randint(0, 7)
            bit = rng.choice([0, max_bit, rng.randint(1, max_bit - 1)])
            dut.inj_en.value = 1
            dut.inj_bank.value = bank
            dut.inj_addr.value = addr
            dut.inj_bit.value = bit
            dut.inj_type.value = ftype

            await jtag_shift_ir(dut, 0x5)  # MBIST_CMD
            cmd = (1 << 5) | (1 << (bank + 1)) | 1  # stop_on_fail=1, bank_mask[bank]=1, start=1
            await jtag_shift_dr(dut, 8, cmd)
            await Timer(300, unit="ns")
            for _ in range(200):
                await RisingEdge(dut.tck)
                if int(dut.bist_done.value) == 1:
                    break
            assert int(dut.bist_fail.value) == 1, f"Fault missed on bank={bank} type={ftype}"

            await jtag_shift_ir(dut, 0x6)  # MBIST_STAT
            stat = await jtag_shift_dr(dut, 48, 0)
            rep_done = stat & 1
            rep_fail = (stat >> 1) & 1
            rep_bank = (stat >> 2) & 0x3
            rep_addr = (stat >> 4) & 0x7
            rep_mask = (stat >> 8) & 0xFFFF_FFFF
            assert rep_done == 1 and rep_fail == 1
            assert rep_bank == bank, f"Bank mismatch: {rep_bank} != {bank}"
            assert rep_addr == addr, f"Addr mismatch: {rep_addr} != {addr}"
            assert rep_mask == (1 << bit), f"Bitmask mismatch: {rep_mask:#x} != {(1 << bit):#x}"

    dut.inj_en.value = 0


@cocotb.test()
async def test_ieee1500_and_scan_xmask_dv(dut):
    """W1500-01/02 & COMP-01/OCC-01: INTEST isolation, EXTEST drive, LOC capture & X-masking."""
    await init_dut(dut)
    dut.test_mode.value = 1

    # Enable JTAG INTEST via W1500 wrapper and verify isolation on sys pins
    await jtag_shift_ir(dut, 0x3)  # INTEST
    await jtag_shift_dr(dut, 97, 1)  # preload core_prog_sel=1
    assert int(dut.x14.value) == 0 and int(dut.pc_obs.value) == 0 and int(dut.alu_obs.value) == 0

    # Verify JTAG EXTEST drives exact boundary outputs outward cleanly
    await jtag_shift_ir(dut, 0x0)  # EXTEST
    extest_vec = (0xA5A5_5A5A << 65) | (0x1234_5678 << 33) | (0xCAFE_BABE << 1)
    await jtag_shift_dr(dut, 97, extest_vec)
    assert int(dut.x14.value) == 0xCAFE_BABE
    assert int(dut.pc_obs.value) == 0x1234_5678
    assert int(dut.alu_obs.value) == 0xA5A5_5A5A

    # Return wrapper to WS_BYPASS via W1500_WIR and leave functional outputs clean
    await jtag_shift_ir(dut, 0x8)  # W1500_WIR
    await jtag_shift_dr(dut, 4, 0x0)  # WS_BYPASS

    # Enable LOC + reset mask + 2:8 compression + X-mask on channel 3
    await jtag_shift_ir(dut, 0x4)  # DFT_CTRL: scan_mode=1, loc=1, rst_mask=1
    await jtag_shift_dr(dut, 8, 0x0B)
    await jtag_shift_ir(dut, 0x7)  # COMP_CFG: comp=1, misr=1, x_mask=0xFF
    await jtag_shift_dr(dut, 16, (0xFF << 3) | 0x3)

    dut.scan_en.value = 1
    for i in range(8):
        await FallingEdge(dut.tck)
        dut.scan_in.value = i & 0x3
        if i == 3:
            dut.sys_rst_n.value = 0  # inject reset glitch during masked shift
        elif i == 5:
            dut.sys_rst_n.value = 1
        await RisingEdge(dut.tck)
        assert int(dut.dft_rst_n.value) == 1, "dft_rst_n leaked 0 during masked test_mode"

    # Drop scan_en -> LOC capture burst -> reload scan_en and verify non-X scan_out
    await FallingEdge(dut.tck)
    dut.scan_en.value = 0
    for _ in range(3):
        await RisingEdge(dut.tck)
    dut.scan_en.value = 1
    for _ in range(8):
        await RisingEdge(dut.tck)
        assert str(dut.scan_out.value) in ("00", "01", "10", "11"), f"Unexpected X on scan_out: {dut.scan_out.value}"
