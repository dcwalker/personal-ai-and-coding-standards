# AGENTS.md

Purpose: AI-specific directives for coding agents. For general coding standards applicable to all contributors, see [CONTRIBUTING.md](CONTRIBUTING.md).

## AI-Specific Behavior Directives

### Planning and Autonomy

- Make a plan before coding and document it in the project's tracking system.
- Stick to the plan; verify each item before marking it complete.
- Never refactor, rename, or reorganize code without explicit approval.
- Ask before creating new files or changing project structure.

### API Integration

- Always consult official API documentation before writing or modifying code that interacts with an API.
  - Do not rely on guessing or trial-and-error.
  - If documentation cannot be found, ask for the spec or reference material.
  - Only use guess-and-check if explicitly approved.

### Memory and State Management

- Use git tools such as diff and reset when reverting changes; do not rely on memory.
- Review all uncommitted changes before committing—commits should be intentional and complete.

### Documentation

- Do not create additional documentation files unless approved or confirmed with the user.

## General Standards

All other coding, testing, commit, and documentation standards are defined in [CONTRIBUTING.md](CONTRIBUTING.md). AI agents must follow those guidelines as well.
