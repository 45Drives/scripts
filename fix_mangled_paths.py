#!/usr/bin/env python3

# written by Joshua Boudreau <jboudreau@45drives.com> 2022

import os
import re
import argparse
import re


def get_unique_name(parent_path, name, taken_paths):
    i = 0
    new_path = os.path.join(parent_path, name)
    extension_dot_ind = name.find('.')
    while new_path in taken_paths or os.path.exists(new_path):
        i += 1
        new_name = name[0:extension_dot_ind] + f"({i})" + name[extension_dot_ind:] if extension_dot_ind != -1 else name + f"({i})"
        new_path = os.path.join(parent_path, new_name)
    taken_paths.append(new_path)
    return new_path


def rename_mangled(paths, dry_run):
    taken_paths = []
    for path in paths:
        for root, dirs, files in os.walk(path, topdown=False):
            for name in [*dirs, *files]:
                new_name = re.sub('[^A-Za-z0-9 _\-,.\(\)]', '_', name, flags=re.MULTILINE)
                if new_name != name:
                    src = os.path.join(root, name)
                    dst = get_unique_name(root, new_name, taken_paths)
                    print(src, ' -> ', dst)
                    if dry_run:
                        continue
                    try:
                        os.rename(src, dst)
                    except OSError as e:
                        print('failed to rename file:', e)


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
