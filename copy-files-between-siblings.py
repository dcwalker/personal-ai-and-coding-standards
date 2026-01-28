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
    '.circleci/helpers/check-eslint-disable.sh',
    '.circleci/helpers/check-markdown-placement.sh',
    '.circleci/helpers/check-unpkg-usage.sh',
    '.cursor',
    '.prettierrc.cjs',
    'AGENTS.md',
    'CONTRIBUTING.md',
    'eslint.config.mjs',
    'eslint-local-rules/index.mjs',
    'eslint-local-rules/no-consecutive-logging.mjs',
    'scripts/list-pr-checks.sh',
    'scripts/list-pr-comments.sh',
    'scripts/list-sonar-issues.sh',
    'scripts/local_deployment_notifier.py',
    'scripts/run-ci-checks-local.sh',
    'scripts/upgrade-all-packages.sh',
]


def get_existing_files(source_dir: Path, files: list[str]) -> list[str]:
    """Check which files or directories exist in the source directory. Returns list of existing paths."""
    existing = []
    for file in files:
        source_path = source_dir / file
        if source_path.exists():
            existing.append(file)
        else:
            print(f'  ⚠ Skipping {file} (not found in source)', file=sys.stderr)
    return existing


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


def select_direction() -> str:
    """Display interactive menu for selecting copy direction. Returns 'to' or 'from'."""
    try:
        questions = [
            inquirer.List(
                'direction',
                message='Select copy direction',
                choices=['Copy to siblings', 'Copy from sibling'],
            ),
        ]
        answers = inquirer.prompt(questions)

        if not answers or 'direction' not in answers:
            print('No direction selected. Exiting.', file=sys.stderr)
            sys.exit(0)

        direction = answers['direction']
        return 'to' if direction == 'Copy to siblings' else 'from'

    except KeyboardInterrupt:
        print('\nSelection cancelled by user.', file=sys.stderr)
        sys.exit(0)
    except Exception as error:
        print(f'Error during direction selection: {error}', file=sys.stderr)
        sys.exit(1)


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


def select_single_directory(directories: list[str]) -> str:
    """Display interactive menu for selecting a single directory. Returns selected directory name."""
    if not directories:
        return ''

    options = sorted(directories)

    try:
        questions = [
            inquirer.List(
                'selected',
                message='Select directory to copy from (use arrow keys to navigate, Enter to confirm)',
                choices=options,
            ),
        ]
        answers = inquirer.prompt(questions)

        if not answers or 'selected' not in answers:
            print('No directory selected. Exiting.', file=sys.stderr)
            sys.exit(0)

        return answers['selected']

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


def copy_directory_to_directory(source_path: Path, target_path: Path, directory: str) -> bool:
    """Copy a directory recursively to target directory. Returns True on success, False on failure."""
    try:
        # Remove target directory if it exists to allow clean copy
        if target_path.exists():
            shutil.rmtree(target_path)
        shutil.copytree(source_path, target_path, dirs_exist_ok=True)
        print(f'  ✓ Copied {directory}')
        return True
    except Exception as error:
        print(f'  ✗ Failed to copy {directory}: {error}', file=sys.stderr)
        return False


def copy_files_to_siblings():
    """Copy files from current repository to selected sibling directories."""
    current_dir = Path.cwd()
    current_dir_name = current_dir.name
    parent_dir = current_dir.parent

    print(f'Current repository: {current_dir_name}')
    print(f'Parent directory: {parent_dir}\n')

    existing_files = get_existing_files(current_dir, FILES_TO_COPY)

    if not existing_files:
        print('No source files found in current directory. Exiting.', file=sys.stderr)
        return

    if len(existing_files) < len(FILES_TO_COPY):
        missing_count = len(FILES_TO_COPY) - len(existing_files)
        print(f'Note: {missing_count} file{"s" if missing_count != 1 else ""} not found in current directory and will be skipped.\n')

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

        for item in existing_files:
            source_path = current_dir / item
            target_path = target_dir / item
            if source_path.is_dir():
                if copy_directory_to_directory(source_path, target_path, item):
                    copied_count += 1
            else:
                if copy_file_to_directory(source_path, target_path, item):
                    copied_count += 1

    print(f'\nCompleted: Copied {copied_count} file{"s" if copied_count != 1 else ""} to {len(selected_directories)} director{"y" if len(selected_directories) == 1 else "ies"}.')


def copy_files_from_sibling():
    """Copy files from a selected sibling directory to current repository."""
    current_dir = Path.cwd()
    current_dir_name = current_dir.name
    parent_dir = current_dir.parent

    print(f'Current repository: {current_dir_name}')
    print(f'Parent directory: {parent_dir}\n')

    directories = get_sibling_directories(parent_dir, current_dir_name)

    if len(directories) == 0:
        print('No sibling directories found.')
        return

    print(f'Found {len(directories)} sibling director{"y" if len(directories) == 1 else "ies"}.\n')

    selected_dir_name = select_single_directory(directories)

    if not selected_dir_name:
        print('No directory selected. Exiting.')
        return

    source_dir = parent_dir / selected_dir_name
    print(f'\nSelected directory: {selected_dir_name}\n')

    existing_files = get_existing_files(source_dir, FILES_TO_COPY)

    if not existing_files:
        print(f'No files found in {selected_dir_name}. Exiting.', file=sys.stderr)
        return

    if len(existing_files) < len(FILES_TO_COPY):
        missing_count = len(FILES_TO_COPY) - len(existing_files)
        print(f'Note: {missing_count} file{"s" if missing_count != 1 else ""} not found in {selected_dir_name} and will be skipped.\n')

    print(f'Copying from {selected_dir_name}...')

    copied_count = 0
    for item in existing_files:
        source_path = source_dir / item
        target_path = current_dir / item
        if source_path.is_dir():
            if copy_directory_to_directory(source_path, target_path, item):
                copied_count += 1
        else:
            if copy_file_to_directory(source_path, target_path, item):
                copied_count += 1

    print(f'\nCompleted: Copied {copied_count} file{"s" if copied_count != 1 else ""} from {selected_dir_name}.')


def main():
    """Main function that handles direction selection and calls appropriate copy function."""
    direction = select_direction()

    if direction == 'to':
        copy_files_to_siblings()
    else:
        copy_files_from_sibling()


if __name__ == '__main__':
    main()
