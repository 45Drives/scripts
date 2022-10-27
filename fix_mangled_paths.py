#!/usr/bin/env python3

# written by Joshua Boudreau <jboudreau@45drives.com> 2022

import os
import re
import argparse
import re

taken_paths = []

def get_unique_name(path):
    i = 0
    new_path = path
    last_dot_ind = path.rfind('.')
    while new_path in taken_paths or os.path.exists(new_path):
        i += 1
        new_path = path[0:last_dot_ind] + f"({i})" + path[last_dot_ind:] if last_dot_ind != -1 else path + f"({i})"
    taken_paths.append(new_path)
    return new_path


def rename_mangled(paths, dry_run):
    for path in paths:
        for root, dirs, files in os.walk(path, topdown=False):
            for name in [*dirs, *files]:
                new_name = re.sub('[^A-Za-z0-9 \n_\-,.\(\)]', '_', name)
                if new_name != name:
                    src = os.path.join(root, name)
                    dst = get_unique_name(os.path.join(root, new_name))
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
