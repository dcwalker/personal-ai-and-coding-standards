/// <reference types="bun-types" />

/**
 * Hook script that continues the agent loop until CI checks pass.
 * This hook is triggered when the agent stops, and checks if CI checks are passing.
 * If not, it instructs the agent to continue fixing errors.
 */

import { execSync } from 'node:child_process';
import type { StopPayload } from 'cursor-hooks';

// Extend StopPayload with loop_count which is in the actual hook input but not in cursor-hooks types
interface StopHookInput extends StopPayload {
  loop_count: number;
}

interface StopHookOutput {
  followup_message?: string;
}

// Read input from stdin using Bun's native JSON parser
let input: StopHookInput;
try {
  input = await Bun.stdin.json();
  // Log hook execution for debugging (visible in Cursor's Hooks output panel)
  console.error(
    `[grind-ci-checks] Hook triggered: status=${input.status}, loop_count=${input.loop_count}, conversation_id=${input.conversation_id}`,
  );
} catch (error) {
  // If we can't parse input, output empty JSON and exit
  console.error(
    `[grind-ci-checks] Error parsing hook input: ${error instanceof Error ? error.message : String(error)}`,
  );
  console.log(JSON.stringify({}));
  process.exit(0);
}

// Exit if agent was aborted or errored
if (input.status !== 'completed') {
  console.log(JSON.stringify({}));
  process.exit(0);
}

// Actually verify if CI checks pass by running the command
let allChecksPassed = false;
try {
  console.error('[grind-ci-checks] Running yarn ci:check...');
  // Run yarn ci:check and capture the exit code
  execSync('yarn ci:check', {
    stdio: 'pipe',
    cwd: process.cwd(),
  });
  allChecksPassed = true;
  console.error('[grind-ci-checks] All CI checks passed!');
} catch (error: any) {
  // If the command exits with non-zero, checks failed
  allChecksPassed = false;
  console.error(
    `[grind-ci-checks] CI checks failed (exit code: ${error?.status || 'unknown'})`,
  );
}

// If all checks passed, we're finished
if (allChecksPassed) {
  console.error(
    `[grind-ci-checks] All checks passed after ${input.loop_count + 1} iteration(s). Stopping.`,
  );
  console.log(JSON.stringify({}));
  process.exit(0);
}

// Check if we've hit the 5-iteration limit
// Cursor enforces a hard 5-iteration limit, so we should warn if approaching it
if (input.loop_count >= 4) {
  console.error(
    `[grind-ci-checks] WARNING: Approaching Cursor's 5-iteration limit (current: ${input.loop_count + 1}/5)`,
  );
}

// Otherwise, continue the loop
const output: StopHookOutput = {
  followup_message: `[Iteration ${input.loop_count + 1}/5] CI checks are still failing. Continue fixing errors by running 'yarn ci:check' and addressing the reported issues.`,
};

console.error(
  `[grind-ci-checks] Continuing loop (iteration ${input.loop_count + 1}/5)`,
);
console.log(JSON.stringify(output));
process.exit(0);
