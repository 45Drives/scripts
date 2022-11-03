#!/usr/bin/env python3

"""
gpt1_from_gpt2.py
Copyright (C) 2022  Josh Boudreau <jboudreau@45drives.com>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
"""

import argparse
import sys
import os
import zlib
import struct
import json
import zipfile
import math
from pathlib import Path
from collections import namedtuple

# constants
LBA = 512
MBR_LEN = 1 * LBA
GPT_HEADER_LEN = 1 * LBA
GPT_TABLE_LEN = 32 * LBA
GPT_LEN = GPT_HEADER_LEN + GPT_TABLE_LEN

CURRENT_LBA_PTR_OFFSET = 0x18
BACKUP_LBA_PTR_OFFSET = 0x20
LBA_PTR_LEN = 8
TABLE_PTR_OFFSET = 0x48
TABLE_PTR_LEN = 8

CRC_OFFSET = 0x10
CRC_LEN = 4


def update_header_checksum(header: bytearray) -> bytearray:
    header[CRC_OFFSET:CRC_OFFSET + CRC_LEN] = struct.pack('<L', 0x0)
    header[CRC_OFFSET:CRC_OFFSET +
           CRC_LEN] = struct.pack('<L', zlib.crc32(header[0:0x5C]))
    return header


def update_header_table_ptr(header: bytearray) -> bytearray:
    header[TABLE_PTR_OFFSET:TABLE_PTR_OFFSET +
           TABLE_PTR_LEN] = struct.pack('<Q', 0x2)
    return header


def swap_header_ptrs(header: bytearray) -> bytearray:
    (
        header[CURRENT_LBA_PTR_OFFSET:CURRENT_LBA_PTR_OFFSET + LBA_PTR_LEN],
        header[BACKUP_LBA_PTR_OFFSET:BACKUP_LBA_PTR_OFFSET + LBA_PTR_LEN]
    ) = (
        header[BACKUP_LBA_PTR_OFFSET:BACKUP_LBA_PTR_OFFSET + LBA_PTR_LEN],
        header[CURRENT_LBA_PTR_OFFSET:CURRENT_LBA_PTR_OFFSET + LBA_PTR_LEN]
    )
    return header


def gpt1_header_from_gpt2_header(header: bytearray) -> bytearray:
    return update_header_checksum(
        update_header_table_ptr(
            swap_header_ptrs(header)))


def get_gpt2(device_path: str) -> bytearray:
    gpt = bytearray(GPT_LEN)
    if not (Path(device_path).is_block_device() or Path(device_path).is_file()):
        print(
            f'Error: {device_path} is not a block device or regular file!', file=sys.stderr)
        sys.exit(1)
    with open(device_path, 'rb') as dev_file:
        dev_file.seek(-GPT_LEN, os.SEEK_END)
        dev_file.readinto(gpt)
    return gpt


def mbr_chs_addr(cylinder: int, head: int, sector: int) -> bytearray:
    return bytearray([head & 0xFF, ((cylinder >> 2) & 0xC0) | (sector & 0x3F), cylinder & 0xFF])


def gpt_mbr_entry() -> bytearray:
    status = 0x0
    first_chs = mbr_chs_addr(0x3FF, 0xFF, 0xFF)  # max
    part_type = 0xEE  # GPT protective MBR
    last_chs = mbr_chs_addr(0x3FF, 0xFF, 0xFF)  # max
    first_lba = 0x1  # start of GPT header
    num_sectors = 0xFFFFFFFF  # max
    return struct.pack('<B3sB3sLL', status, first_chs, part_type, last_chs, first_lba, num_sectors)


def gen_mbr() -> bytearray:
    mbr = bytearray(LBA)
    mbr[0x1BE:0x1CE] = gpt_mbr_entry()
    mbr[-2:] = [0x55, 0xAA]  # boot signature
    return mbr


def main():
    parser = argparse.ArgumentParser(
        description='Generate MBR + primary GPT from intact secondary GPT')
    parser.add_argument('input_device', metavar='BLOCK_DEVICE',
                        type=str, help='Path to block device containing secondary GPT')
    args = parser.parse_args()
    gpt1 = bytearray(GPT_LEN)
    gpt2 = get_gpt2(args.input_device)
    gpt1[0:GPT_HEADER_LEN] = gpt1_header_from_gpt2_header(
        gpt2[-GPT_HEADER_LEN:])
    gpt1[GPT_HEADER_LEN:] = gpt2[0:-GPT_HEADER_LEN]
    sys.stdout.buffer.write(gen_mbr() + gpt1)


if __name__ == "__main__":
    main()
