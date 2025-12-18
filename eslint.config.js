import js from '@eslint/js';
import globals from 'globals';
import typescriptEslintPlugin from '@typescript-eslint/eslint-plugin';
import tsParser from '@typescript-eslint/parser';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { FlatCompat } from '@eslint/eslintrc';
import prettierConfig from 'eslint-config-prettier';
import jsdoc from 'eslint-plugin-jsdoc';
import localRules from './eslint-local-rules/index.js';

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
      'lint-staged.config.js',
      'test/helpers/**/*.js',
      'test/jest_setup.ts',
      '*.config.js',
      '.prettierrc.js',
      'eslint-rules/**/*',
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
      'eslint-local-rules/no-consecutive-logging': 'error',
      '@typescript-eslint/interface-name-prefix': 'off',
      '@typescript-eslint/explicit-function-return-type': 'error',
      '@typescript-eslint/explicit-module-boundary-types': 'off',
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-empty-function': 'error',
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
        },
      ],
      'multiline-comment-style': ['error', 'starred-block'],
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
    rules: {
      // Overrides '@typescript-eslint/explicit-function-return-type': 'error'
      '@typescript-eslint/explicit-function-return-type': 'off',
      // Overrides '@typescript-eslint/no-explicit-any': 'error'
      '@typescript-eslint/no-explicit-any': 'warn',
      // Overrides 'jsdoc/require-description': 'error'
      'jsdoc/require-description': 'off',
      // Additional test-specific rules (not overriding primary rules)
      '@typescript-eslint/no-unsafe-assignment': 'warn',
      '@typescript-eslint/no-unsafe-call': 'warn',
      '@typescript-eslint/no-unsafe-member-access': 'warn',
      '@typescript-eslint/no-unsafe-function-type': 'off',
      '@typescript-eslint/unbound-method': 'warn',
    },
  },
  prettierConfig,
];
