import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


@cocotb.test()
async def test_counter4_basic(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst.value = 1
    dut.en.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    dut.en.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert int(dut.q.value) == 5, f"Expected 5, got {int(dut.q.value)}"
