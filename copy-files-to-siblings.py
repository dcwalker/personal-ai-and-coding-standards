#!/usr/bin/env python3

import os
import shutil
import sys
from pathlib import Path

FILES_TO_COPY = ['AGENTS.md', 'CONTRIBUTING.md']


def copy_files_to_siblings():
    current_dir = Path.cwd()
    current_dir_name = current_dir.name
    parent_dir = current_dir.parent

    print(f'Current repository: {current_dir_name}')
    print(f'Parent directory: {parent_dir}\n')

    # Verify source files exist
    for file in FILES_TO_COPY:
        source_path = current_dir / file
        if not source_path.exists():
            print(f'Error: {file} not found in current directory', file=sys.stderr)
            sys.exit(1)

    # Read parent directory
    try:
        entries = list(parent_dir.iterdir())
    except Exception as error:
        print(f'Error reading parent directory: {error}', file=sys.stderr)
        sys.exit(1)

    # Filter to only directories, excluding current repo
    directories = [
        entry.name
        for entry in entries
        if entry.is_dir() and entry.name != current_dir_name
    ]

    if len(directories) == 0:
        print('No sibling directories found.')
        return

    print(f'Found {len(directories)} sibling director{"y" if len(directories) == 1 else "ies"}:')
    for dir_name in directories:
        print(f'  - {dir_name}')
    print('')

    # Copy files to each sibling directory
    copied_count = 0
    for dir_name in directories:
        target_dir = parent_dir / dir_name
        print(f'Copying to {dir_name}...')

        for file in FILES_TO_COPY:
            source_path = current_dir / file
            target_path = target_dir / file

            try:
                shutil.copy2(source_path, target_path)
                print(f'  ✓ Copied {file}')
                copied_count += 1
            except Exception as error:
                print(f'  ✗ Failed to copy {file}: {error}', file=sys.stderr)

    print(f'\nCompleted: Copied {copied_count} file{"s" if copied_count != 1 else ""} to {len(directories)} director{"y" if len(directories) == 1 else "ies"}.')


if __name__ == '__main__':
    copy_files_to_siblings()

