# Contributing Guidelines

This document outlines our coding standards, documentation practices, and testing expectations to help maintain consistency and quality across the codebase.

## Planning

Before diving into implementation, we encourage you to:

- Create a plan for your changes and document it in the project's tracking system
- Have your plan reviewed and confirmed before beginning implementation
- Ensure your work aligns with the project goals defined in the README

This helps ensure we're all moving in the same direction and prevents duplicate effort.

## Coding Standards

### General Principles

- **Clarity over cleverness**: Write code that's easy to understand and maintain
- **Brevity over verbosity**: Be concise, but not at the expense of clarity
- **Follow DRY principles**: Centralize shared logic and prefer reusable CSS classes over inline styles

### Configuration and Environment

- Avoid hard-coding URLs or other environment-specific attributes
- Keep configuration values and constants centralized (e.g., in `config/` directories or `env.sample`)
- Document all environment variables in a table within the README

### API Integration

When working with external APIs:

- Consult official API documentation before writing or modifying integration code
- If you can't find documentation, please ask for the specification or reference material
- Avoid relying on trial-and-error approaches

### Code Maintenance

- **Remove dead code** rather than commenting it out—version control preserves history
- Assume backward compatibility is not required unless explicitly stated
- Design with a mobile-first approach and architect APIs before UIs when possible
- Favor lightweight user interfaces with centralized business logic

### Code Quality

- Keep comments factual and focused on describing the current state
- Maintain a tidy codebase by removing typos, stale comments, misleading names, and unused imports
- Never include personally identifiable information (PII) or sensitive data in the project
- Use git tools like `diff` and `reset` when reverting changes

### Dependencies

- Bundle dependencies locally—avoid loading them dynamically from CDNs or services like unpkg.com

## Testing

We take testing seriously to maintain code quality:

- All automated tests and linters must pass before committing
- Respect test coverage thresholds if defined—lowering thresholds should not be used as a workaround
- Avoid disabling or skipping linting rules or tests just to make code pass
- Write tests that describe behavior through specific, concrete examples rather than vague statements
- Ensure both tests and documentation accurately reflect the implementation before committing

## Commit Messages

Clear commit messages help everyone understand the project's evolution:

- Prefix each commit with the issue or task ID from the branch name (e.g., `PROJECT-123: Add user authentication`)
- If no issue exists, consider creating one to track the work
- When working on a child task, you may optionally append the parent issue ID for traceability
- Keep commit messages professional—avoid emojis or subjective commentary
- Review all uncommitted changes before committing to ensure the commit is intentional and complete
- Avoid including debug code or temporary changes
- Reference the relevant issue or ticket for major decisions, either in the commit message, an ADR, or an inline comment

## Documentation

Good documentation makes the project accessible to everyone:

### README Guidelines

- Keep the README accurate and reflective of the current implementation
- Exclude future plans or historical information
- Organize the README doc in this order:
  - **Introduction**: State the project's purpose, use cases, what it provides, and list key features (one sentence each)
  - **Table of Contents**: A navigation aid and an overview of all the content
  - **Usage**: Provide concise instructions and examples for common use cases
  - **Installation and Configuration**: List required and optional steps with their purpose and examples
  - **Technical Details**: Include architecture diagrams, process flows, and sequence diagrams using Mermaid when helpful

### Additional Documentation

- If the project requires permissions, maintain a Permissions section in the README describing each one, what access it grants, which features depend on it, and link to official documentation
- Consider maintaining a Glossary of Terms in the README for consistent language across code and UI
- Update documentation and diagrams whenever the implementation changes—they should always describe the current state
- If the project has API endpoints available, then maintain a detailed `openapi.yaml` doc in the project

## Log Levels

When adding logging to the application, use these standard levels:

**TRACE**  
Ultra-detailed diagnostic information including fine-grained internal state, step-by-step operations, and verbose algorithm flow. Typically only enabled during deep debugging.

**DEBUG**  
Developer-oriented diagnostics with useful checkpoints, variable values, decisions, and execution flow that aid debugging but aren't needed during normal operation.

**INFO**  
High-level operational events describing normal behavior, such as starting or completing a task, handling a request, or performing a scheduled operation.

**WARN**  
Unusual or unexpected behavior that didn't stop execution. Something may require attention, but the system continued running successfully.

**ERROR**  
A failure that prevented a task or invocation from completing normally. This includes exceptions, failed API calls, or unrecoverable conditions.

**FATAL**  
A severe failure that stops execution and requires immediate attention.

### Forge-Specific Error Handling

In Forge apps, error handling follows a selective re-throw pattern to support Forge's built-in monitoring:

- Non-transient errors (auth failures, configuration errors, not found) should be re-thrown after logging to trigger Forge's invocation monitoring. This ensures app owners are alerted when the success rate drops below 99%.
- Transient errors (rate limits, timeouts, 5xx errors) should be logged but not re-thrown to avoid unnecessary alert noise. These errors are expected to resolve on retry.

Use the `isTransientError()` helper function in `src/index.ts` to classify errors before deciding whether to re-throw.

---

Thank you for helping make this project better! If you have questions about these guidelines, please don't hesitate to ask.
