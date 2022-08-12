#!/usr/bin/env python3

"""
dump_part_info.py
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
from pathlib import Path
from collections import namedtuple

LBA = 512


def bytearray2hex(raw: bytearray, join_with: str = '', fmt: str = '02X') -> str:
    return join_with.join(format(byte, fmt) for byte in raw)


def decode_uint8(raw: bytearray, endianness: str = '<') -> int:
    return struct.unpack(endianness + 'B', raw)[0]


def decode_uint16(raw: bytearray, endianness: str = '<') -> int:
    return struct.unpack(endianness + 'H', raw)[0]


def decode_uint32(raw: bytearray, endianness: str = '<') -> int:
    return struct.unpack(endianness + 'L', raw)[0]


def decode_uint64(raw: bytearray, endianness: str = '<') -> int:
    return struct.unpack(endianness + 'Q', raw)[0]


def decode_guid(raw: bytearray) -> str:
    little_endians = "{:0>8X}-{:0>4X}-{:0>4X}".format(
        *struct.unpack('<LHH', raw[:8]))
    byte_array1 = bytearray2hex(raw[8:10])
    byte_array2 = bytearray2hex(raw[10:])
    return f'{little_endians}-{byte_array1}-{byte_array2}'


def partitioned(raw: bytearray, size: int):
    return [raw[i:i + size] for i in range(0, len(raw), size)]


def check_chksum(section: bytearray, chksum: int):
    result = zlib.crc32(section)
    return {
        'valid': chksum == result,
        'calculated': result,
        'should_be': chksum,
    }


def check_header_chksum(header: bytearray):
    crc_offset = 0x10
    crc_area_len = 0x5C
    section = header[0:crc_area_len]
    chksum = decode_uint32(section[crc_offset:crc_offset + 4])
    section[crc_offset:crc_offset + 4] = [0] * 4  # must be zeroed
    return check_chksum(section, chksum)


def extract_gpt_header_info(header: bytearray):
    GPTHeaderStruct = namedtuple(
        'GPTHeaderStruct',
        'signature '
        'revision '
        'header_size '
        'header_crc '
        'res1 '
        'current_lba '  # location of this header
        'backup_lba '  # location of backup copy
        'first_partition_lba '
        'last_partition_lba '
        'disk_guid_bytearray '
        'partition_entries_start '
        'partition_entries_count '
        'partition_entry_size '
        'partition_entries_crc '
        'res2'
    )
    raw_header = GPTHeaderStruct._make(
        struct.unpack(
            '<'  # use little-endian
            '8s'  # signature
            '4s'  # revision
            'L'  # header_size
            'L'  # header_crc
            '4s'  # reserved
            'Q'  # current_lba
            'Q'  # backup_lba
            'Q'  # first_partition_lba
            'Q'  # last_partition_lba
            '16s'  # disk_guid
            'Q'  # partition_entries_start
            'L'  # partition_entries_count
            'L'  # partition_entry_size
            'L'  # partition_entries_crc
            '420s',  # reserved
            header
        )
    )
    return {
        'signature': raw_header.signature.decode('ascii', errors='backslashreplace'),
        'checksum': check_header_chksum(header),
        'lba_indices': {
            'this_gpt_header': raw_header.current_lba,
            'other_gpt_header': raw_header.backup_lba,
            'first_partition': raw_header.first_partition_lba,
            'last_partition': raw_header.last_partition_lba,
            'entry_table_start': raw_header.partition_entries_start,
        },
        'entry_table_info': {
            'lba_index': raw_header.partition_entries_start,
            'entry_count': raw_header.partition_entries_count,
            'entry_size': raw_header.partition_entry_size,
            'crc': raw_header.partition_entries_crc,
        }
    }


def extract_gpt_entry_attributes(flags: int):
    return {
        'raw': flags,
        'platform_required': bool(flags & (1 << 0)),
        'efi_should_ignore': bool(flags & (1 << 1)),
        'legacy_bios_bootable': bool(flags & (1 << 2)),
    }


def extract_gpt_entry(entry_raw: bytearray):
    GPTEntryStruct = namedtuple(
        'GPTEntryStruct',
        'type_guid '
        'unique_guid '
        'first_lba '
        'last_lba '
        'attribute_flags '
        'name'
    )
    raw_fields = GPTEntryStruct._make(struct.unpack(
        '<'  # little-endian
        '16s'
        '16s'
        'Q'
        'Q'
        'Q'
        '72s',
        entry_raw
    ))
    return {
        'type_guid': decode_guid(raw_fields.type_guid),
        'unique_guid': decode_guid(raw_fields.unique_guid),
        'first_lba': raw_fields.first_lba,
        'last_lba': raw_fields.last_lba,
        'attributes': extract_gpt_entry_attributes(raw_fields.attribute_flags),
        'name': raw_fields.name.decode('utf-16', errors='backslashreplace').replace('\u0000', '')
    }


def extract_gpt_entries(entries_raw: bytearray, entry_info: dict):
    entries = {
        "checksum": check_chksum(entries_raw, entry_info['crc'])
    }
    entry_size = 0x80
    for (i, entry_raw) in enumerate(partitioned(entries_raw, entry_size)):
        if not all(byte == 0 for byte in entry_raw):
            entries[f'p{i + 1}'] = extract_gpt_entry(entry_raw)
    return entries


def extract_gpt_info(header_raw: bytearray, entries_raw: bytearray):
    header = extract_gpt_header_info(header_raw)
    return {
        'header': header,
        'entries': extract_gpt_entries(
            entries_raw, header["entry_table_info"])
    }


def get_gpt(dev_path: str):
    primary_gpt_raw = bytearray(33 * LBA)
    secondary_gpt_raw = bytearray(33 * LBA)
    with open(dev_path, 'rb') as dev_file:
        dev_file.seek(1 * LBA)
        dev_file.readinto(primary_gpt_raw)
        primary_gpt = extract_gpt_info(
            primary_gpt_raw[0:LBA], primary_gpt_raw[LBA:])
        assumed_secondary_gpt_entries_offset = dev_file.seek(
            -1 * len(secondary_gpt_raw), os.SEEK_END)
        dev_file.readinto(secondary_gpt_raw)
        secondary_gpt = extract_gpt_info(
            secondary_gpt_raw[-LBA:], secondary_gpt_raw[:-LBA])
        secondary_gpt["header"]["lba_indices"]["meta"] = {
            'secondary_gpt_entries_after_last_partition_lba': assumed_secondary_gpt_entries_offset == (
                primary_gpt["header"]["lba_indices"]["last_partition"] + 1) * LBA
        }
        return {
            'primary': primary_gpt,
            'secondary': secondary_gpt,
        }


# def get_zfs_nvlist(dev_path: str):

def validate_args(args):
    valid = True
    if not Path(args.input_device).exists():
        print(
            f'Error: {args.input_device} does not exist!', file=sys.stderr)
        valid = False
    elif not Path(args.input_device).is_block_device():
        print(
            f'Warning: {args.input_device} is not a block device!', file=sys.stderr)
        if not Path(args.input_device).is_file():
            print(
                f'Error: {args.input_device} is not a block device or regular file!', file=sys.stderr)
            valid = False
    return valid


def rip_images(dev_path: str, archive: zipfile.ZipFile):
    with open(dev_path, 'rb') as dev_file:
        archive.writestr('LBA0_LBA33_MBR_GPT1.img', dev_file.read(34 * LBA))
        dev_file.seek(-33 * LBA, os.SEEK_END)
        archive.writestr('LBA-33_LBA-0_GPT2.img', dev_file.read())


def rip_zfs(dev_path: str, archive: zipfile.ZipFile, gpt_info: dict, use_secondary: bool):
    gpt = 'secondary' if use_secondary else 'primary'
    ZFS_LABEL_LEN = 256 * 1024
    with open(dev_path, 'rb') as dev_file:
        # part1 (ZFS)
        # whole labels
        zfs_data_start = gpt_info[gpt]['entries']['p1']['first_lba'] * LBA
        zfs_data_end = (gpt_info[gpt]['entries']
                        ['p1']['last_lba'] + 1) * LBA  # exclusive
        dev_file.seek(zfs_data_start)
        archive.writestr('ZFS_vdev_label_0.img', dev_file.read(ZFS_LABEL_LEN))
        archive.writestr('ZFS_vdev_label_1.img', dev_file.read(ZFS_LABEL_LEN))
        dev_file.seek(zfs_data_end - (2 * ZFS_LABEL_LEN))
        dev_file.seek(-2 * ZFS_LABEL_LEN, os.SEEK_CUR)
        archive.writestr('ZFS_vdev_label_2.img', dev_file.read(ZFS_LABEL_LEN))
        archive.writestr('ZFS_vdev_label_3.img', dev_file.read(ZFS_LABEL_LEN))
        # nv_pairs
        NVLIST_OFFSET = 16 * 1024
        NVLIST_LENGTH = (128 - 16) * 1024
        dev_file.seek(zfs_data_start + NVLIST_OFFSET)
        archive.writestr('ZFS_vdev_label_0_nvlist.img', dev_file.read(NVLIST_LENGTH))
        dev_file.seek(ZFS_LABEL_LEN - NVLIST_LENGTH, os.SEEK_CUR)
        archive.writestr('ZFS_vdev_label_1_nvlist.img', dev_file.read(NVLIST_LENGTH))
        dev_file.seek(zfs_data_end - (2 * ZFS_LABEL_LEN) + NVLIST_OFFSET)
        archive.writestr('ZFS_vdev_label_2_nvlist.img', dev_file.read(NVLIST_LENGTH))
        dev_file.seek(ZFS_LABEL_LEN - NVLIST_LENGTH, os.SEEK_CUR)
        archive.writestr('ZFS_vdev_label_3_nvlist.img', dev_file.read(NVLIST_LENGTH))
        # part9 (Solaris Reserved 1, 8M usually)
        PART9_START = gpt_info[gpt]['entries']['p9']['first_lba'] * LBA
        PART9_END = (gpt_info[gpt]['entries']
                        ['p9']['last_lba'] + 1) * LBA  # exclusive
        PART9_LEN = PART9_END - PART9_START
        dev_file.seek(PART9_START)
        archive.writestr('ZFS_solaris_reserved.img', dev_file.read(PART9_LEN))


def main():
    parser = argparse.ArgumentParser(description='Dump block device GPT and ZFS label info')
    parser.add_argument('input_device', metavar='BLOCK_DEVICE',
                        type=str, help='Path to block device to dump')
    parser.add_argument('out_path', metavar='OUTPUT[.zip]',
                        help='Path to store outputs as zip archive [optional]', nargs='?', default=None)
    parser.add_argument('-q', '--quiet', action='store_true',
                        help='Silence output, for when you only want the zip')
    parser.add_argument('-z', '--zfs', action='store_true',
                        help='Try to rip ZFS labels into archive')
    parser.add_argument('-s', '--secondary', action='store_true', help='Use secondary GPT table while trying to rip ZFS images')

    args = parser.parse_args()

    if not validate_args(args):
        sys.exit(1)

    gpt_info_json = ""

    gpt_info = get_gpt(args.input_device)

    gpt_info_json = json.dumps(gpt_info, indent=2)

    if not args.quiet:
        print(gpt_info_json)

    if args.out_path:
        out_path = Path(args.out_path)
        if (out_path.suffix != '.zip'):
            out_path = out_path.with_suffix(out_path.suffix + '.zip')
        if (out_path.exists()):
            print(f'Error: {str(out_path)} exists!')
            sys.exit(1)
        with zipfile.ZipFile(out_path, mode='w', allowZip64=True, compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('gpt_info.json', gpt_info_json)
            rip_images(args.input_device, archive)
            if args.zfs:
                rip_zfs(args.input_device, archive, gpt_info, args.secondary)


if __name__ == "__main__":
    main()
