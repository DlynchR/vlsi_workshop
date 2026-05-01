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
AN0_BIT      = 5
AN1_BIT      = 6
AN2_BIT      = 7

# Hex to 7-seg pattern (active-low, bit order seg[6:0] = a b c d e f g)
HEX_TO_SEG = {
    0x0: 0b1000000, 0x1: 0b1111001, 0x2: 0b0100100, 0x3: 0b0110000,
    0x4: 0b0011001, 0x5: 0b0010010, 0x6: 0b0000010, 0x7: 0b1111000,
    0x8: 0b0000000, 0x9: 0b0010000, 0xA: 0b0001000, 0xB: 0b0000011,
    0xC: 0b1000110, 0xD: 0b0100001, 0xE: 0b0000110, 0xF: 0b0001110,
}


def _set_uio_bit(dut, bit, value):
    cur = int(dut.uio_in.value)
    if value:
        cur |= (1 << bit)
    else:
        cur &= ~(1 << bit)
    dut.uio_in.value = cur


async def spi_transfer(dut, tx_byte, half_period=4):
    """Drive an 8-bit SPI transaction as the master (Mode 0, MSB first)."""
    received = 0

    _set_uio_bit(dut, CS_N_BIT, 0)
    await ClockCycles(dut.clk, half_period)

    for i in range(8):
        bit = (tx_byte >> (7 - i)) & 1
        _set_uio_bit(dut, MOSI_BIT, bit)
        await ClockCycles(dut.clk, half_period)

        _set_uio_bit(dut, SCK_BIT, 1)
        await ClockCycles(dut.clk, half_period)
        miso_bit = (int(dut.uio_out.value) >> MISO_BIT) & 1
        received = (received << 1) | miso_bit

        _set_uio_bit(dut, SCK_BIT, 0)
        await ClockCycles(dut.clk, half_period)

    _set_uio_bit(dut, CS_N_BIT, 1)
    await ClockCycles(dut.clk, half_period * 4)
    return received


async def wait_for_active_digit(dut, target_an_pattern, timeout=200):
    """Wait until uio_out's an[2:0] equals target_an_pattern (active-low)."""
    for _ in range(timeout):
        an = (int(dut.uio_out.value) >> AN0_BIT) & 0b111
        if an == target_an_pattern:
            return
        await ClockCycles(dut.clk, 1)
    raise TimeoutError(f"Digit {target_an_pattern:03b} never became active")


def get_seg(dut):
    return int(dut.uo_out.value) & 0x7F


@cocotb.test()
async def test_spi_to_7seg(dut):
    dut._log.info("Start SPI -> 7seg test")

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = (1 << CS_N_BIT)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    test_bytes = [0x3C, 0xA5, 0x07, 0xFE]
    for b in test_bytes:
        dut.ui_in.value = 0  # nothing special on MISO
        await spi_transfer(dut, b)
        await ClockCycles(dut.clk, 5)

        rx_internal = int(dut.user_project.u_spi_slave.rx_data.value)
        dut._log.info(f"sent=0x{b:02X}  slave rx_data=0x{rx_internal:02X}")
        assert rx_internal == b, f"rx_data mismatch: got 0x{rx_internal:02X}, expected 0x{b:02X}"

        # Right digit = low nibble
        await wait_for_active_digit(dut, 0b110)
        seg = get_seg(dut)
        expected = HEX_TO_SEG[b & 0xF]
        dut._log.info(f"byte=0x{b:02X}  right digit seg=0b{seg:07b} expected=0b{expected:07b}")
        assert seg == expected, f"right digit: got 0b{seg:07b}, expected 0b{expected:07b}"

        # Center digit = high nibble
        await wait_for_active_digit(dut, 0b101)
        seg = get_seg(dut)
        expected = HEX_TO_SEG[(b >> 4) & 0xF]
        dut._log.info(f"byte=0x{b:02X}  center digit seg=0b{seg:07b} expected=0b{expected:07b}")
        assert seg == expected, f"center digit: got 0b{seg:07b}, expected 0b{expected:07b}"

        # Left digit = always 0 ({4'h0, rx_data})
        await wait_for_active_digit(dut, 0b011)
        seg = get_seg(dut)
        expected = HEX_TO_SEG[0]
        assert seg == expected, f"left digit: got 0b{seg:07b}, expected 0b{expected:07b}"
