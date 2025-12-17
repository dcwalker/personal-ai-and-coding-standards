## Purpose

These files define coding standards, documentation practices, and testing expectations for this project:

- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Guidelines for all contributors (human and AI) covering coding standards, testing, documentation, and commit practices.
- **[AGENTS.md](AGENTS.md)**: AI-specific directives for coding agents, including behavioral constraints and memory management.

Together, they help ensure that responses, code, and documentation follow consistent expectations.

## Usage

### Copy Files to Sibling Repositories

The `copy-files-to-siblings.py` script copies `AGENTS.md` and `CONTRIBUTING.md` to all sibling directories in the parent folder. This is useful for maintaining consistent coding standards across multiple repositories.

To use the script:

```bash
python3 copy-files-to-siblings.py
```

The script will:

- Find all sibling directories in the parent folder
- Copy `AGENTS.md` and `CONTRIBUTING.md` to each sibling directory
- Report the number of files copied and target directories

Note: The script excludes the current repository from the copy operation.
