#!/usr/bin/env python3

# written by Joshua Boudreau <jboudreau@45drives.com> 2022

import os
import re
import argparse
import re


def get_unique_name(root, name, taken_paths):
    i = 0
    extension_dot_ind = name.find('.')
    new_name = name
    new_path = os.path.join(root, new_name)
    while new_path in taken_paths or os.path.exists(new_path):
        i += 1
        new_name = name[0:extension_dot_ind] + f"({i})" + name[extension_dot_ind:] if extension_dot_ind != -1 else name + f"({i})"
        new_path = os.path.join(root, new_name)
    taken_paths.append(new_path)
    return new_name


def rename_mangled(paths, dry_run):
    taken_paths = []
    def rename_entries(root, entries, rootfd):
        changes = []
        for src in entries:
            dst = re.sub('[^A-Za-z0-9 _\-,.\(\)\'+!@]', '_', src, flags=re.MULTILINE)
            if dst != src:
                dst = get_unique_name(root, dst, taken_paths)
                print(os.path.join(root, src), ' -> ', os.path.join(root, dst))
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
        for root, dirs, files, rootfd in os.fwalk(path, topdown=True):
            if '.zfs' in dirs:
                dirs.remove('.zfs')
            rename_entries(root, dirs, rootfd)
            rename_entries(root, files, rootfd)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('roots', type=str, nargs='+', metavar='ROOT_PATH')
    # parser.add_argument('-d', '--dry-run', action='store_true', default=False)
    args = parser.parse_args()
    rename_mangled(args.roots, True) # dry run
    response = input("is this okay? [y/N]: ")
    if response.upper() in ['Y', 'YES']:
        rename_mangled(args.roots, False) # really rename


if __name__ == '__main__':
    main()
