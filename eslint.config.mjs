import js from '@eslint/js';
import globals from 'globals';
import typescriptEslintPlugin from '@typescript-eslint/eslint-plugin';
import tsParser from '@typescript-eslint/parser';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { FlatCompat } from '@eslint/eslintrc';
import prettierConfig from 'eslint-config-prettier';
import jestPlugin from 'eslint-plugin-jest';
import jsdoc from 'eslint-plugin-jsdoc';
import localRules from './eslint-local-rules/index.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const compat = new FlatCompat({
  baseDirectory: __dirname,
  recommendedConfig: js.configs.recommended,
  allConfig: js.configs.all,
});

export default [
  {
    ignores: [
      'static/**/*',
      'node_modules/**/*',
      'reports/**/*',
      'coverage/**/*',
      'dist/**/*',
      'lint-staged.config.js',
      'eslint.config.mjs',
      'test/helpers/**/*.js',
      'test/jest_setup.ts',
      '*.config.{js,cjs,mjs}',
      '.prettierrc.cjs',
      'eslint-local-rules/**/*',
      'scripts/**/*.js',
      '.cursor/**/*',
    ],
  },
  js.configs.recommended,
  ...compat.extends(
    'plugin:@typescript-eslint/eslint-recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:@typescript-eslint/recommended-type-checked',
  ),
  {
    files: ['**/*'],
    plugins: {
      'eslint-local-rules': localRules,
      '@typescript-eslint': typescriptEslintPlugin,
      jsdoc,
    },
    rules: {
      // What the rule does: Prevents consecutive logging statements. Consecutive log calls should be consolidated into a single log message using newlines for formatting.
      'eslint-local-rules/no-consecutive-logging': 'error',

      // What the rule does: Requires explicit return type annotations on all functions and methods. This improves code readability and can help catch type errors early.
      '@typescript-eslint/explicit-function-return-type': 'error',

      // What the rule does: Disallows the use of the 'any' type, requiring more specific types. This enforces type safety throughout the codebase.
      '@typescript-eslint/no-explicit-any': 'error',
      // Type-aware rules disabled due to false positives with Forge API types and dynamic code patterns
      // These rules require strict typing that conflicts with Forge's API design

      // What the rule does: Disallows empty function bodies. Empty functions are often a sign of incomplete implementation or unnecessary code.
      // Override from: @typescript-eslint/recommended (enabled as 'error')
      // Why disabled: Disabled because Forge API patterns often require empty functions as placeholders or for interface compliance.
      '@typescript-eslint/no-empty-function': 'off',

      // What the rule does: Requires async functions to contain at least one await expression. Functions marked as async without await are unnecessary and can be simplified.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled because Forge API patterns sometimes require async functions that delegate to other async functions without direct await usage.
      '@typescript-eslint/require-await': 'off',

      // What the rule does: Disallows assigning values with 'any' type to variables. This prevents the spread of 'any' types through the codebase.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled due to Forge API types that use 'any' in their type definitions, causing false positives.
      '@typescript-eslint/no-unsafe-assignment': 'off',

      // What the rule does: Disallows calling functions typed as 'any'. This prevents calling functions without type safety guarantees.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled because Forge API methods are often typed as 'any' or use dynamic typing patterns.
      '@typescript-eslint/no-unsafe-call': 'off',

      // What the rule does: Disallows accessing properties on values typed as 'any'. This prevents accessing properties without type safety guarantees.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled because Forge API objects use dynamic property access patterns that trigger false positives.
      '@typescript-eslint/no-unsafe-member-access': 'off',

      // What the rule does: Disallows returning values typed as 'any' from functions. This prevents propagating 'any' types through function return values.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled due to Forge API return types that use 'any' in their type definitions.
      '@typescript-eslint/no-unsafe-return': 'off',

      // What the rule does: Disallows passing 'any' typed values as function arguments. This prevents passing untyped values to functions that expect specific types.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled because Forge API methods accept 'any' typed parameters.
      '@typescript-eslint/no-unsafe-argument': 'off',

      // What the rule does: Restricts template literal expressions to specific types (strings, numbers, etc.). This ensures type safety in template strings.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled because Forge API patterns use dynamic values in template strings that trigger false positives.
      '@typescript-eslint/restrict-template-expressions': 'off',

      // What the rule does: Disallows calling toString() on values that may not be strings or may not have a meaningful string representation. This prevents runtime errors from invalid toString() calls.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled because Forge API objects use dynamic typing that conflicts with this rule.
      '@typescript-eslint/no-base-to-string': 'off',

      // What the rule does: Disallows using unbound methods (methods called without their 'this' context). This prevents runtime errors from methods that depend on 'this' being called incorrectly.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled because Forge API patterns sometimes require passing methods as callbacks.
      '@typescript-eslint/unbound-method': 'off',

      // What the rule does: Disallows awaiting values that are not Promises or thenable objects. This prevents awaiting non-async values which is a common mistake.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled because Forge API methods sometimes return values that are typed as 'any' but are actually Promises.
      '@typescript-eslint/await-thenable': 'off',

      // What the rule does: Disallows using Promises in contexts where they're not expected (e.g., conditionals, array methods). This prevents common mistakes where Promises are used incorrectly.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled because Forge API patterns sometimes require Promise handling that triggers false positives.
      '@typescript-eslint/no-misused-promises': 'off',

      // What the rule does: Disallows Promises that are created but not awaited or handled. This prevents unhandled promise rejections and ensures proper error handling.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled because Forge API patterns sometimes intentionally create unhandled Promises for fire-and-forget operations.
      '@typescript-eslint/no-floating-promises': 'off',

      // What the rule does: Restricts the + operator to operands of compatible types (both numbers or both strings). This prevents accidental string concatenation or type coercion bugs.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled: Disabled because Forge API patterns use dynamic typing that conflicts with this rule.
      '@typescript-eslint/restrict-plus-operands': 'off',

      // What the rule does: Disallows unnecessary escape characters in strings and regular expressions. This helps identify escape sequences that don't need to be escaped.
      // Override from: js.configs.recommended (enabled as 'error')
      // Why disabled: Disabled because it conflicts with some Forge API string patterns and regex requirements.
      'no-useless-escape': 'off',

      // What the rule does: Disallows unused variables, parameters, and imports. This helps identify dead code and ensures all declared variables are actually used.
      // Override from: @typescript-eslint/recommended (enabled as 'error', replaces base 'no-unused-vars')
      // Why disabled: Disabled because Forge API patterns and dynamic property access create situations where variables appear unused but are actually needed. Re-enable when codebase is refactored to use stricter typing patterns.
      '@typescript-eslint/no-unused-vars': [
        'off',
        {
          argsIgnorePattern: '^_',
        },
      ],

      // What the rule does: Ensures that only Error objects (or allowed exceptions) are thrown, preventing throwing of non-Error values. This improves error handling and stack trace quality.
      '@typescript-eslint/only-throw-error': [
        'error',
        {
          allowThrowingAny: false,
          allowThrowingUnknown: false,
          allow: ['InvocationError'],
        },
      ],

      // What the rule does: Enforces the use of starred-block style (/* */) for multiline comments instead of consecutive line comments. This maintains consistent comment formatting.
      'multiline-comment-style': ['error', 'starred-block'],

      // What the rule does: Requires JSDoc comments to include a description for all documented items. This ensures documentation is complete and useful.
      'jsdoc/require-description': 'error',
    },
  },
  {
    files: ['**/*.js'],
    languageOptions: {
      ecmaVersion: 2020,
      sourceType: 'module',
      globals: {
        ...globals.node,
      },
    },
  },
  {
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: {
      ecmaVersion: 2020,
      sourceType: 'module',
      globals: {
        ...globals.node,
        ...globals.jest,
      },
      parser: tsParser,
      parserOptions: {
        project: './tsconfig.json',
      },
    },
  },
  {
    files: ['**/*.spec.ts', '**/*.test.ts', '**/*.test.tsx', '**/*.spec.tsx'],
    plugins: {
      jest: jestPlugin,
    },
    languageOptions: {
      ecmaVersion: 2020,
      sourceType: 'module',
      globals: {
        ...globals.node,
        ...globals.jest,
      },
      parser: tsParser,
      parserOptions: {
        project: './tsconfig.json',
      },
    },
    rules: {
      // What the rule does: Prevents skipped tests (it.skip, describe.skip, test.skip, xit, xdescribe, xtest). This ensures all tests run and helps prevent accidentally committed skipped tests.
      'jest/no-disabled-tests': 'error',

      // What the rule does: Requires explicit return type annotations on all functions and methods. This improves code readability and can help catch type errors early.
      // Override from: main config (enabled as 'error')
      // Why disabled in tests: Allows test functions to omit explicit return types for flexibility. Test code often uses inferred types for brevity and readability.
      '@typescript-eslint/explicit-function-return-type': 'off',

      // What the rule does: Disallows the use of the 'any' type, requiring more specific types. This enforces type safety throughout the codebase.
      // Override from: main config (enabled as 'error')
      // Why disabled in tests: Allows use of 'any' type in test files. This is necessary for creating flexible mocks and test fixtures that don't require full type definitions.
      '@typescript-eslint/no-explicit-any': 'off',

      // What the rule does: Requires JSDoc comments to include a description for all documented items. This ensures documentation is complete and useful.
      // Override from: main config (enabled as 'error')
      // Why disabled in tests: Allows JSDoc comments without descriptions in test files. This reduces documentation overhead for test code where the code itself is often self-explanatory.
      'jsdoc/require-description': 'off',

      // What the rule does: Disallows unnecessary type assertions (e.g., 'as Type' when TypeScript can already infer the type). This helps identify redundant type assertions.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled in tests: Allows unnecessary type assertions in test files. Jest mocks and test utilities often require type assertions that would be flagged as unnecessary in production code.
      '@typescript-eslint/no-unnecessary-type-assertion': 'off',

      // What the rule does: Disallows unsafe function types (functions typed as 'any' or with unsafe signatures). This prevents using function types that lack type safety.
      // Override from: @typescript-eslint/recommended-type-checked (enabled as 'error')
      // Why disabled in tests: Allows unsafe function types in test files. Jest mocks and test utilities often use function types that would be flagged as unsafe in production code.
      '@typescript-eslint/no-unsafe-function-type': 'off',
    },
  },
  prettierConfig,
];

