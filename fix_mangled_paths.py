#!/usr/bin/env python3

# written by Joshua Boudreau <jboudreau@45drives.com> 2022

import os
import argparse
import sys


def get_unique_name(root, name, taken_paths):
    i = 0
    ext_ind = name.find('.')
    new_name = name
    new_path = os.path.join(root, new_name)
    while new_path in taken_paths or os.path.exists(new_path):
        i += 1
        new_name = (
            name[0:ext_ind] + f"({i})" + name[ext_ind:]
            if ext_ind != -1 else name + f"({i})"
        )
        new_path = os.path.join(root, new_name)
    taken_paths.append(new_path)
    return new_name


def legalize_name(string: str):
    windows_ill = ['\\', '/', ':', '*', '?', '"', '<', '>', '|']
    def printable(c): return ord(c) in range(0x20, 0x7F)
    def windows_allowed(c): return c not in windows_ill
    # weird case of long dash instead of '-'
    string = string.replace(u'–', '-')
    return "".join(map(lambda c: c if printable(c) and windows_allowed(c) else '_', string))


def rename_mangled(paths, dry_run, recursive):
    taken_paths = []
    change_count = 0

    def rename_entries(root, entries, rootfd):
        changes = []
        nonlocal change_count
        for src in entries:
            dst = legalize_name(src)
            if dst != src:
                dst = get_unique_name(root, dst, taken_paths)
                print('in', f"'{root.encode('unicode_escape').decode('utf-8')}':")
                print(f"'{src.encode('unicode_escape').decode('utf-8')}'", '->')
                print(f"'{dst.encode('unicode_escape').decode('utf-8')}'")
                print()
                change_count += 1
                if dry_run:
                    continue
                try:
                    os.rename(src, dst, src_dir_fd=rootfd, dst_dir_fd=rootfd)
                    changes.append((src, dst))
                except OSError as e:
                    print('failed to rename file:', e)
        for src, dst in changes:
            entries.remove(src)
            entries.append(dst)
    for path in paths:
        if os.path.isdir(path) and recursive:
            for root, dirs, files, rootfd in os.fwalk(path, topdown=True):
                if '.zfs' in dirs:
                    dirs.remove('.zfs')
                rename_entries(root, dirs, rootfd)
                rename_entries(root, files, rootfd)
        if os.path.exists(path):
            fullpath = os.path.realpath(path)
            root = os.path.dirname(fullpath)
            entries = [os.path.basename(fullpath)]
            rootfd = os.open(root, os.O_RDONLY)
            rename_entries(root, entries, rootfd)
    return change_count


def main():
    parser = argparse.ArgumentParser(
        description='Rename files and directories to play nice with Windows')
    parser.add_argument('roots', type=str, nargs='+', metavar='PATH',
                        help='Path(s) to rename')
    parser.add_argument('-r', '--recursive', action='store_true', default=False, help='Recurse into directories')
    args = parser.parse_args()
    mangled_count = rename_mangled(args.roots, True, args.recursive)  # dry run
    print(f"Found {mangled_count} invalid paths")
    if mangled_count == 0:
        sys.exit()
    response = input("Are the above changes okay? [y/N]: ")
    if response.upper() in ['Y', 'YES']:
        rename_mangled(args.roots, False, args.recursive)  # really rename


if __name__ == '__main__':
    main()
