---
name: fix-ci-checks
description: Run yarn ci:check and automatically fix all errors until all CI checks pass. Use when you need to fix linting, formatting, type errors, or test failures.
---

# Fix CI Checks

This skill runs the CI check script (`yarn ci:check`) and automatically fixes all errors until all checks pass.

## When to Use

- Use this skill when you want to fix all CI check errors automatically
- Use when you've made code changes and need to ensure they pass all checks
- Use when preparing code for commit or pull request

## Instructions

When invoked, follow these steps:

1. **Run the CI check script**: Execute `yarn ci:check` and capture the full output, including exit code.

2. **Analyze the results**:
   - If the exit code is 0, all checks passed. You're done.
   - If the exit code is non-zero, identify which checks failed from the output.

3. **Fix errors systematically**: For each failed check, fix the errors:
   - **depcheck**: Remove unused dependencies or add missing ones
   - **format:check**: Run `yarn format` to auto-fix formatting issues
   - **lint:check**: Run `yarn lint:eslint` to auto-fix linting issues (or manually fix if auto-fix doesn't work)
   - **typecheck**: Fix TypeScript type errors in the reported files
   - **check-eslint-disable**: Remove or justify eslint-disable comments as needed
   - **check-markdown-placement**: Move markdown files to correct locations
   - **check-unpkg-usage**: Replace unpkg.com references with proper dependencies
   - **test:cov**: Fix failing tests or update test expectations

4. **Iterate**: After fixing errors, run `yarn ci:check` again. Continue this cycle until:
   - All checks pass (exit code 0), OR
   - You've reached a maximum of 5 iterations (Cursor's hard limit for stop hooks)

5. **Report**: When all checks pass (exit code 0):
   - Summarize which checks were fixed
   - Report final status
   - The hook will automatically verify checks passed and stop looping

   If some issues remain that can't be auto-fixed:
   - Document them in the summary
   - Ask the user for guidance on manual fixes needed
   - The hook will detect that checks still fail and continue the loop

   **Note**: Cursor enforces a hard 5-iteration limit for stop hooks. If 5 iterations are insufficient:
   - The hook will stop after 5 iterations
   - You can manually continue by invoking this skill again
   - The skill will pick up where it left off

## Important Notes

- Always run the full `yarn ci:check` command to see all errors at once
- Fix errors in order of dependency (e.g., type errors before lint errors)
- Some checks may require manual intervention (e.g., test logic changes)
- If a check keeps failing after multiple attempts, ask the user for guidance

## Example Workflow

```
1. Run: yarn ci:check
2. See: format:check and lint:check failed
3. Fix: Run yarn format and yarn lint:eslint
4. Run: yarn ci:check again
5. See: typecheck failed
6. Fix: Address TypeScript errors in reported files
7. Run: yarn ci:check again
8. See: All checks passed ✓
```
