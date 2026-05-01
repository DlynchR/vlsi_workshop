# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# uio bit map (must match info.yaml / project.v)
SCK_BIT      = 0
CS_N_BIT     = 1
MOSI_BIT     = 2
MISO_BIT     = 3
RX_VALID_BIT = 4


def _set_uio_bit(dut, bit, value):
    cur = int(dut.uio_in.value)
    if value:
        cur |= (1 << bit)
    else:
        cur &= ~(1 << bit)
    dut.uio_in.value = cur


async def spi_transfer(dut, tx_byte, half_period=4):
    """Drive an 8-bit SPI transaction as the master (Mode 0, MSB first).
    Returns the byte shifted out by the slave on MISO.
    `half_period` is in system-clock cycles."""
    received = 0

    # CS low -> slave latches tx_data from ui_in
    _set_uio_bit(dut, CS_N_BIT, 0)
    await ClockCycles(dut.clk, half_period)

    for i in range(8):
        bit = (tx_byte >> (7 - i)) & 1
        # Setup MOSI while SCK is low
        _set_uio_bit(dut, MOSI_BIT, bit)
        await ClockCycles(dut.clk, half_period)

        # Rising edge of SCK -> slave samples MOSI; master samples MISO
        _set_uio_bit(dut, SCK_BIT, 1)
        # Wait synchronizer (2 FF) + sample to propagate
        await ClockCycles(dut.clk, half_period)
        miso_bit = (int(dut.uio_out.value) >> MISO_BIT) & 1
        received = (received << 1) | miso_bit

        # Falling edge -> slave shifts MISO
        _set_uio_bit(dut, SCK_BIT, 0)
        await ClockCycles(dut.clk, half_period)

    # CS high
    _set_uio_bit(dut, CS_N_BIT, 1)
    await ClockCycles(dut.clk, half_period * 4)

    return received


@cocotb.test()
async def test_spi_slave(dut):
    dut._log.info("Start SPI slave test")

    # System clock: 100 MHz (10 ns)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # Idle: CS high, SCK low (Mode 0)
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = (1 << CS_N_BIT)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    # --- Transaction 1 ---
    dut.ui_in.value = 0xA5      # byte the slave will send back on MISO
    mosi_byte = 0x3C
    miso_byte = await spi_transfer(dut, mosi_byte)
    await ClockCycles(dut.clk, 5)

    rx = int(dut.uo_out.value)
    dut._log.info(f"MOSI=0x{mosi_byte:02X}  uo_out=0x{rx:02X}  MISO=0x{miso_byte:02X}")
    assert rx == mosi_byte, f"Expected uo_out=0x{mosi_byte:02X}, got 0x{rx:02X}"

    # --- Transaction 2 ---
    dut.ui_in.value = 0x5A
    mosi_byte = 0xC3
    miso_byte = await spi_transfer(dut, mosi_byte)
    await ClockCycles(dut.clk, 5)

    rx = int(dut.uo_out.value)
    dut._log.info(f"MOSI=0x{mosi_byte:02X}  uo_out=0x{rx:02X}  MISO=0x{miso_byte:02X}")
    assert rx == mosi_byte, f"Expected uo_out=0x{mosi_byte:02X}, got 0x{rx:02X}"