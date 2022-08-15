# dump_part_info.py
Print GPT info as JSON, and optionally store in zip archive along with images of GPT and ZFS vdev label sectors of disk.
```
usage: dump_part_info.py [-h] [-q] [-z] [-s] BLOCK_DEVICE [OUTPUT[.zip]]

Dump block device GPT and ZFS label info

positional arguments:
  BLOCK_DEVICE     Path to block device to dump
  OUTPUT[.zip]     Path to store outputs as zip archive [optional]

options:
  -h, --help       show this help message and exit
  -q, --quiet      Silence output, for when you only want the zip
  -z, --zfs        Try to rip ZFS labels into archive
  -s, --secondary  Use secondary GPT table while trying to rip ZFS images
```

# gpt1_from_gpt2.py
If the primary GPT is corrupt but the secondary GPT is fine, use this to generate a primary GPT image.  
**REMEMBER `seek=1` WHEN WRITING TO DISK TO SKIP MBR**
```
usage: gpt1_from_gpt2.py [-h] BLOCK_DEVICE

Generate primary GPT from intact secondary GPT

positional arguments:
  BLOCK_DEVICE  Path to block device to dump

options:
  -h, --help    show this help message and exit
```
## Example
```bash
./gpt1_from_gpt2.py /dev/sdi > gpt.img
# type carefully:
dd if=gpt.img bs=512 seek=1 count=33 of=/dev/sdi
```
# Extracting Partition Info from ZFS Physcial vDev
Costumer has missing partitions on four drives in a raidz2 pool. We need to see if partition data is still there but only the GPT table is missing.
## GUID Partition Table (GPT) Info
### GPT Disk Format
|     LBA |     offset | offset (hex) | relative offset | relative offset (hex) | description                    |
| ------: | ---------: | -----------: | --------------: | --------------------: | ------------------------------ |
|       0 |          0 |            0 |                 |                       | MBR                            |
|       1 |        512 |          200 |                 |                       | Primary GPT Header             |
|   **2** |   **1024** |      **400** |          **+0** |              **+000** | **Entry 1 (ZFS Data)**         |
|         |       1152 |          480 |            +128 |                  +080 | Entry 2                        |
|         |       1280 |          500 |            +256 |                  +100 | Entry 3                        |
|         |       1408 |          580 |            +384 |                  +180 | Entry 4                        |
|       3 |       1536 |          600 |            +512 |                  +200 | Entry 5                        |
|         |       1664 |          680 |            +640 |                  +280 | Entry 6                        |
|         |       1792 |          700 |            +768 |                  +300 | Entry 7                        |
|         |       1920 |          780 |            +896 |                  +380 | Entry 8                        |
|   **4** |   **2048** |      **800** |       **+1024** |              **+400** | **Entry 9 (Solaris Reserved)** |
|         |            |              |                 |                       | Entries 10..128 ...            |
|      34 |       2176 |          880 |                 |                       | Data Partition 1               |
|         |            |              |                 |                       | Remaining Partitions ...       |
| **-33** | **-16896** |    **-4200** |          **+0** |              **+000** | **Entry 1 (ZFS Data)**         |
|         |     -16768 |        -4180 |            +128 |                  +080 | Entry 2                        |
|         |     -16640 |        -4100 |            +256 |                  +100 | Entry 3                        |
|     -32 |     -16512 |        -4080 |            +384 |                  +180 | Entry 4                        |
|         |     -16384 |        -4000 |            +512 |                  +200 | Entry 5                        |
|         |     -16256 |        -3F80 |            +640 |                  +280 | Entry 6                        |
|         |     -16128 |        -3F00 |            +768 |                  +300 | Entry 7                        |
|         |     -16000 |        -3E80 |            +896 |                  +380 | Entry 8                        |
| **-31** | **-15872** |    **-3E00** |       **+1024** |              **+400** | **Entry 9 (Solaris Reserved)** |
|         |            |              |                 |                       | Entries 10..128                |
|      -1 |       -512 |         -200 |                 |                       | Secondary GPT Header           |

#### GPT Header Format (LBA 1)
| Offset    | Length   | Contents                                                                                                               |
| --------- | -------- | ---------------------------------------------------------------------------------------------------------------------- |
| 0  (0x00) | 8 bytes  | Signature ("EFI PART", 45h 46h 49h 20h 50h 41h 52h 54h)                                                                |
| 8  (0x08) | 4 bytes  | Revision 1.0 (00h 00h 01h 00h) for UEFI 2.8                                                                            |
| 12 (0x0C) | 4 bytes  | Header size in little endian (in bytes, usually 5Ch 00h 00h 00h or 92 bytes)                                           |
| 16 (0x10) | 4 bytes  | CRC32 of header (offset +0 to +0x5b) in little endian, with this field zeroed during calculation                       |
| 20 (0x14) | 4 bytes  | Reserved; must be zero                                                                                                 |
| 24 (0x18) | 8 bytes  | Current LBA (location of this header copy)                                                                             |
| 32 (0x20) | 8 bytes  | Backup LBA (location of the other header copy)                                                                         |
| 40 (0x28) | 8 bytes  | First usable LBA for partitions (primary partition table last LBA + 1)                                                 |
| 48 (0x30) | 8 bytes  | Last usable LBA (secondary partition table first LBA − 1)                                                              |
| 56 (0x38) | 16 bytes | Disk GUID in mixed endian                                                                                              |
| 72 (0x48) | 8 bytes  | Starting LBA of array of partition entries (always 2 in primary copy)                                                  |
| 80 (0x50) | 4 bytes  | Number of partition entries in array                                                                                   |
| 84 (0x54) | 4 bytes  | Size of a single partition entry (usually 80h or 128)                                                                  |
| 88 (0x58) | 4 bytes  | CRC32 of partition entries array in little endian                                                                      |
| 92 (0x5C) | *        | Reserved; zeros for rest of block (420 bytes for a sector size of 512 bytes; but can be more with larger sector sizes) |

#### GPT Entry Format (LBA 2..33)
| Offset    | Length   | Contents                                |
| --------- | -------- | --------------------------------------- |
| 0  (0x00) | 16 bytes | Partition type GUID (mixed endian)      |
| 16 (0x10) | 16 bytes | Unique partition GUID (mixed endian)    |
| 32 (0x20) | 8 bytes  | First LBA index (little endian)         |
| 40 (0x28) | 8 bytes  | Last LBA index (inclusive, usually odd) |
| 48 (0x30) | 8 bytes  | Attribute flags                         |
| 56 (0x38) | 72 bytes | Partition name (36 UTF-16LE code units) |

Offset / 0x200 = Offset / 512 = LBA index

GPT header start: 0x200 (LBA1)
GPT header size: 0x200
GPT table start: 0x400
GPT table entry size: 0x80

## ZFS vDev
|    Offset |  Length | Length (hex) | Contents              |
| --------: | ------: | -----------: | :-------------------- |
|  0x000000 |    256K |     0x040000 | Label 0               |
|  0x040000 |    256K |     0x040000 | Label 1               |
|  0x080000 | 57,344K |     0x380000 | Reserved (boot block) |
|  0x400000 |       - |            - | Allocatable space     |
| -0x080000 |    256K |     0x040000 | Label 2               |
| -0x040000 |    256K |     0x040000 | Label 3               |

### ZFS vDev Label
|  Offset | Length | Length (hex) | Contents                                       |
| ------: | -----: | -----------: | :--------------------------------------------- |
| 0x00000 |     8K |      0x02000 | Blank                                          |
| 0x02000 |     8K |      0x02000 | Reserved (Boot header)                         |
| 0x04000 |   112K |      0x1C000 | name-value list (XDR) desc. vdev relationships |
| 0x20000 |   128K |      0x20000 | Uberblock array                                |

## Commands
### Dump LBA Sector(s)
```bash
dd if=/dev/sdX bs=512 skip=LBA_INDEX count=LBA_COUNT
```
#### Examples
- dump MBR + primary GPT to file:
	```bash
	dd if=/dev/sda bs=512 skip=0 count=34 of=sda_MBR_GPT1.img
	```
- dump only primary GPT header of /dev/sda to file:
	```bash
	dd if=/dev/sda bs=512 skip=1 count=1 of=sda_GPT1_header.img
	```
- dump only primary GPT entries of /dev/sda to file:
	```bash
	dd if=/dev/sda bs=512 skip=2 count=32 of=sda_GPT1_entries.img
	```
- e.g. view table entry 1 as canonical hex:
	```bash
	dd if=/dev/sda bs=512 skip=2 count=1 | hexdump -Cv | less
	```
