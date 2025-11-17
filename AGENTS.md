# AGENTS.md

Purpose: Defines coding, documentation, and testing standards for all project contributors and AI agents.  

## Planning
- Make a plan before coding and document it in the project’s tracking system.  
- Do not begin implementation until the plan has been reviewed and confirmed.  
- Ensure that all new work, implementation strategies, and architecture align with the project goals defined in the README.  

## Coding
- Prefer clarity over cleverness, brevity over verbosity.  
- Make a plan before coding and document it in the project’s tracking system.  
- Stick to the plan; verify each item before marking it complete.  
- Follow DRY principles. Centralize shared logic; prefer reusable CSS classes over inline styles.  
- URLs and other environment-specific attributes must never be hard-coded.  
- Keep configuration values and constants centralized (config/, .env.example, etc.).  
- Document all environment variables in a table within the README.  
- Always consult official API documentation before writing or modifying code that interacts with an API.  
  - Do not rely on guessing or trial-and-error.  
  - If documentation cannot be found, ask for the spec or reference material.  
  - Only use guess-and-check if explicitly approved.  
- Delete dead code instead of commenting it out — version control tracks history.  
- Assume backward compatibility is not required unless stated.  
- Design mobile-first, architect API-first. Favor lightweight UIs and centralized logic.  
- Comments must be factual and describe the current state only.  
- Maintain a tidy codebase: remove typos, stale comments, misleading names, and unused imports.  
- Never include PII or sensitive information anywhere in the project.  
- Use git tools such as diff and reset when reverting changes; do not rely on memory.  
- Bundle dependencies locally. Do not load dynamically from CDNs or unpkg.com.  
- Never refactor, rename, or reorganize code without explicit approval.  
- Ask before creating new files or changing project structure.  

## Testing
- All automated tests and linters must pass before committing.  
- Respect test coverage thresholds if defined — lowering thresholds is not a fix.  
- Never disable or skip linting rules or tests to make code pass.  
- Write tests that describe behavior through specific, concrete examples — not vague statements.  
- Before committing, ensure that both tests pass and documentation accurately reflects the current implementation state.  

## Commit Messages
- Prefix each commit with the issue or task ID derived from the branch name (e.g., PROJECT-123).  
- If no issue or task is linked, pause and confirm whether one should be created before proceeding.  
- When the branch represents a child task, optionally append the parent issue or epic ID at the end of the message for traceability.  
- No emojis or subjective commentary.  
- Review all uncommitted changes before committing — commits should be intentional and complete.  
- Do not include debug or superfluous code.  
- Each major decision should be reflected in a commit message, ADR, or inline comment referencing the relevant issue or ticket.  

## Documentation
- Keep the README accurate to the current implementation. Exclude future plans or history.  
- The Introduction must state the project’s purpose and use cases, summarize what the project provides, and list key features in one sentence each.  
- Usage section: concise instructions and examples for common cases.  
- Installation and Configuration: required and optional steps, their purpose, and examples.  
- Technical Details: architecture diagrams, process flow, and sequence diagrams using Mermaid.  
- Maintain a Permissions section in the README describing each required permission, what access it grants, what features depend on it, and include links to official documentation.  
- Maintain a Glossary of Terms for consistent language across code and UI.  
- Update documentation and diagrams whenever implementation changes; they must always describe the current state.  
- Do not create additional documentation files unless approved or confirmed with the user.  

## Log Levels
TRACE  
Ultra-detailed diagnostic information. Includes fine-grained internal state, step-by-step operations, and verbose algorithm flow. Typically only enabled during deep debugging.  

DEBUG  
Developer-oriented diagnostics. Useful checkpoints, variable values, decisions, and execution flow that aid debugging but are not needed in normal operation.  

INFO  
High-level operational events describing normal behavior. Indicates that meaningful actions occurred, such as starting or completing a task, handling a request, or performing a scheduled operation.  

WARN  
Indicates unusual or unexpected behavior that did not stop execution. Something may be wrong or require attention, but the system continued running successfully.  

ERROR  
A failure that prevented a task or invocation from completing normally. Includes exceptions, failed API calls, or unrecoverable conditions. Anything resulting in an ERROR log should be bubbled up as an uncaught exception.  

FATAL  
A severe failure that stops execution and requires immediate attention. Anything resulting in a FATAL log should be bubbled up as an uncaught exception.  
