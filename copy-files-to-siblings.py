#!/usr/bin/env python3

import os
import shutil
import sys
from pathlib import Path

try:
    import inquirer
except ImportError:
    print('Error: inquirer package is required. Install it with: pip3 install inquirer', file=sys.stderr)
    sys.exit(1)

FILES_TO_COPY = [
    'AGENTS.md',
    'CONTRIBUTING.md',
    'eslint.config.mjs',
    '.prettierrc.cjs',
    'eslint-local-rules/index.mjs',
    'eslint-local-rules/no-consecutive-logging.mjs',
    'scripts/list-sonar-issues.sh',
    'scripts/list-pr-comments.sh',
]


def verify_source_files(current_dir: Path):
    """Verify that all source files exist in the current directory."""
    for file in FILES_TO_COPY:
        source_path = current_dir / file
        if not source_path.exists():
            print(f'Error: {file} not found in current directory', file=sys.stderr)
            sys.exit(1)


def get_sibling_directories(parent_dir: Path, current_dir_name: str) -> list[str]:
    """Read parent directory and return list of sibling directory names."""
    try:
        entries = list(parent_dir.iterdir())
    except Exception as error:
        print(f'Error reading parent directory: {error}', file=sys.stderr)
        sys.exit(1)

    directories = [
        entry.name
        for entry in entries
        if entry.is_dir() and entry.name != current_dir_name
    ]
    return directories


def select_directories(directories: list[str]) -> list[str]:
    """Display interactive menu for selecting directories. Returns list of selected directory names."""
    if not directories:
        return []

    # Create menu options with "All" at the top
    options = ['All'] + sorted(directories)

    try:
        questions = [
            inquirer.Checkbox(
                'selected',
                message='Select directories to copy to (use arrow keys to navigate, space to select, Enter to confirm)',
                choices=options,
            ),
        ]
        answers = inquirer.prompt(questions)

        if not answers or 'selected' not in answers or not answers['selected']:
            print('No directories selected. Exiting.', file=sys.stderr)
            sys.exit(0)

        selected = answers['selected']

        # Handle "All" selection
        if 'All' in selected:
            if len(selected) == 1:
                # Only "All" selected, return all directories
                return directories
            else:
                # "All" plus others selected, treat as all directories
                return directories

        return selected

    except KeyboardInterrupt:
        print('\nSelection cancelled by user.', file=sys.stderr)
        sys.exit(0)
    except Exception as error:
        print(f'Error during directory selection: {error}', file=sys.stderr)
        sys.exit(1)


def copy_file_to_directory(source_path: Path, target_path: Path, file: str) -> bool:
    """Copy a single file to target directory. Returns True on success, False on failure."""
    try:
        target_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, target_path)
        print(f'  ✓ Copied {file}')
        return True
    except Exception as error:
        print(f'  ✗ Failed to copy {file}: {error}', file=sys.stderr)
        return False


def copy_files_to_siblings():
    current_dir = Path.cwd()
    current_dir_name = current_dir.name
    parent_dir = current_dir.parent

    print(f'Current repository: {current_dir_name}')
    print(f'Parent directory: {parent_dir}\n')

    verify_source_files(current_dir)

    directories = get_sibling_directories(parent_dir, current_dir_name)

    if len(directories) == 0:
        print('No sibling directories found.')
        return

    print(f'Found {len(directories)} sibling director{"y" if len(directories) == 1 else "ies"}.\n')

    selected_directories = select_directories(directories)

    if not selected_directories:
        print('No directories selected. Exiting.')
        return

    print(f'\nSelected {len(selected_directories)} director{"y" if len(selected_directories) == 1 else "ies"} for copying.\n')

    copied_count = 0
    for dir_name in selected_directories:
        target_dir = parent_dir / dir_name
        print(f'Copying to {dir_name}...')

        for file in FILES_TO_COPY:
            source_path = current_dir / file
            target_path = target_dir / file
            if copy_file_to_directory(source_path, target_path, file):
                copied_count += 1

    print(f'\nCompleted: Copied {copied_count} file{"s" if copied_count != 1 else ""} to {len(selected_directories)} director{"y" if len(selected_directories) == 1 else "ies"}.')


if __name__ == '__main__':
    copy_files_to_siblings()

