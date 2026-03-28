#!/usr/bin/env python3
import argparse
import mmap
import os
import struct
import time

import serial


FRAME_LEN = 16

REG_CTRL = 0x00
REG_BUDGET = 0x04
REG_REQ = 0x08
REG_IO = 0x0C
REG_TEMP_A = 0x10
REG_TEMP_B = 0x14

REG_STATUS0 = 0x20
REG_STATUS1 = 0x24
REG_EFF = 0x28
REG_INPUT_ECHO = 0x2C
REG_SAMPLE_COUNTER = 0x30


class Mmio32:
    def __init__(self, base_addr: int, span: int = 0x1000):
        self.base_addr = base_addr
        self.span = span
        self.page_size = mmap.PAGESIZE
        self.page_base = base_addr & ~(self.page_size - 1)
        self.page_off = base_addr - self.page_base

        self.fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        self.mm = mmap.mmap(
            self.fd,
            self.page_off + span,
            mmap.MAP_SHARED,
            mmap.PROT_READ | mmap.PROT_WRITE,
            offset=self.page_base,
        )

    def close(self):
        self.mm.close()
        os.close(self.fd)

    def read32(self, offset: int) -> int:
        self.mm.seek(self.page_off + offset)
        return struct.unpack("<I", self.mm.read(4))[0]

    def write32(self, offset: int, value: int):
        self.mm.seek(self.page_off + offset)
        self.mm.write(struct.pack("<I", value & 0xFFFFFFFF))


class Bridge:
    def __init__(self, mmio: Mmio32, ser: serial.Serial):
        self.mmio = mmio
        self.ser = ser
        self.frame_ctr = 0
        self.expect_temp = None

    def _set_bit(self, reg_off: int, bit: int, val: int):
        cur = self.mmio.read32(reg_off)
        if val:
            cur |= (1 << bit)
        else:
            cur &= ~(1 << bit)
        self.mmio.write32(reg_off, cur)

    def handle_command(self, cmd: int):
        if self.expect_temp is not None:
            self.mmio.write32(self.expect_temp, cmd & 0x7F)
            self.expect_temp = None
            return

        if cmd == 0xA0:
            self._set_bit(REG_CTRL, 0, 0)
        elif cmd == 0xA1:
            self._set_bit(REG_CTRL, 0, 1)
        elif cmd == 0xF0:
            self._set_bit(REG_CTRL, 1, 0)
        elif cmd == 0xF1:
            self._set_bit(REG_CTRL, 1, 1)

        elif 0xB0 <= cmd <= 0xB7:
            self.mmio.write32(REG_BUDGET, cmd & 0x07)

        elif 0xC0 <= cmd <= 0xC3:
            cur = self.mmio.read32(REG_REQ)
            cur = (cur & ~0x3) | (cmd & 0x3)
            self.mmio.write32(REG_REQ, cur)
        elif 0xC4 <= cmd <= 0xC7:
            cur = self.mmio.read32(REG_REQ)
            cur = (cur & ~(0x3 << 2)) | ((cmd & 0x3) << 2)
            self.mmio.write32(REG_REQ, cur)

        elif cmd == 0xD0:
            self._set_bit(REG_IO, 0, 0)
        elif cmd == 0xD1:
            self._set_bit(REG_IO, 0, 1)
        elif cmd == 0xD2:
            self._set_bit(REG_IO, 1, 0)
        elif cmd == 0xD3:
            self._set_bit(REG_IO, 1, 1)
        elif cmd == 0xD4:
            self._set_bit(REG_IO, 2, 0)
        elif cmd == 0xD5:
            self._set_bit(REG_IO, 2, 1)
        elif cmd == 0xD6:
            self._set_bit(REG_IO, 3, 0)
        elif cmd == 0xD7:
            self._set_bit(REG_IO, 3, 1)

        elif cmd == 0xE0:
            self.expect_temp = REG_TEMP_A
        elif cmd == 0xE1:
            self.expect_temp = REG_TEMP_B

    def build_frame(self) -> bytes:
        status0 = self.mmio.read32(REG_STATUS0)
        status1 = self.mmio.read32(REG_STATUS1)
        eff = self.mmio.read32(REG_EFF)
        echo = self.mmio.read32(REG_INPUT_ECHO)
        _sample = self.mmio.read32(REG_SAMPLE_COUNTER)

        host_mode = (status0 >> 0) & 0x1
        alarm_a = (status0 >> 1) & 0x1
        alarm_b = (status0 >> 2) & 0x1
        clk_en_a = (status0 >> 3) & 0x1
        clk_en_b = (status0 >> 4) & 0x1
        grant_a = (status0 >> 5) & 0x3
        grant_b = (status0 >> 7) & 0x3
        ws_phase = (status0 >> 9) & 0x7

        current_budget = (status1 >> 0) & 0x7
        budget_headroom = (status1 >> 3) & 0x7

        temp_a = (echo >> 0) & 0x7F
        temp_b = (echo >> 8) & 0x7F
        act_a = (echo >> 15) & 0x1
        stall_a = (echo >> 16) & 0x1
        act_b = (echo >> 17) & 0x1
        stall_b = (echo >> 18) & 0x1
        req_a = (echo >> 19) & 0x3
        req_b = (echo >> 21) & 0x3

        b2 = self.frame_ctr & 0xFF
        b3 = (self.frame_ctr >> 8) & 0xFF
        b4 = ((clk_en_b << 4) | (clk_en_a << 3) | (alarm_b << 2) | (alarm_a << 1) | host_mode) & 0xFF
        b5 = ((grant_b << 2) | grant_a) & 0xFF
        b6 = ((budget_headroom << 3) | current_budget) & 0xFF
        b7 = eff & 0xFF
        b8 = (eff >> 8) & 0x03
        b9 = temp_a & 0x7F
        b10 = temp_b & 0x7F
        b11 = ((act_b << 3) | (stall_b << 2) | (act_a << 1) | stall_a) & 0xFF
        b12 = ((req_b << 2) | req_a) & 0xFF
        b13 = ws_phase & 0x07

        csum = 0
        for x in [b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13]:
            csum ^= x

        self.frame_ctr = (self.frame_ctr + 1) & 0xFFFF

        return bytes([
            0xAA, 0x55,
            b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13,
            csum,
            0x0D,
        ])

    def run(self, hz: float):
        period = 1.0 / hz
        next_send = time.time()

        while True:
            data = self.ser.read(64)
            if data:
                for b in data:
                    self.handle_command(b)

            now = time.time()
            if now >= next_send:
                self.ser.write(self.build_frame())
                next_send = now + period



def main():
    parser = argparse.ArgumentParser(description="PS UART bridge for PL power governor")
    parser.add_argument("--base", default="0x43C00000", help="AXI base address (hex)")
    parser.add_argument("--port", default="/dev/ttyPS0", help="PS UART device")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--hz", type=float, default=5.0)
    args = parser.parse_args()

    base = int(args.base, 16)

    mmio = Mmio32(base)
    ser = serial.Serial(args.port, args.baud, timeout=0.01)

    try:
        bridge = Bridge(mmio, ser)
        bridge.run(args.hz)
    finally:
        ser.close()
        mmio.close()


if __name__ == "__main__":
    main()
