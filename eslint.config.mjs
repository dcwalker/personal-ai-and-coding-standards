import typescriptEslintEslintPlugin from '@typescript-eslint/eslint-plugin';
import globals from 'globals';
import tsParser from '@typescript-eslint/parser';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';
import js from '@eslint/js';
import { FlatCompat } from '@eslint/eslintrc';
import jsdoc from 'eslint-plugin-jsdoc';
import customRules from './eslint-local-rules/index.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const hasTsConfig = existsSync(path.join(__dirname, 'tsconfig.json'));
const compat = new FlatCompat({
  baseDirectory: __dirname,
  recommendedConfig: js.configs.recommended,
  allConfig: js.configs.all,
});

export default [
  {
    ignores: [
      '**/lint-staged.config.js',
      'static/**/*',
      'src/**/*.js',
      'jest.config.js',
      '*.config.js',
      'scripts/**/*',
      '.prettierrc.js',
      'eslint-rules/**/*',
    ],
  },
  ...compat.extends(
    'plugin:@typescript-eslint/eslint-recommended',
    'plugin:@typescript-eslint/recommended',
    'prettier',
  ),
  {
    plugins: {
      '@typescript-eslint': typescriptEslintEslintPlugin,
      jsdoc,
      'custom-rules': customRules,
    },

    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.jest,
      },

      parser: tsParser,
      ecmaVersion: 5,
      sourceType: 'module',

      ...(hasTsConfig && {
        parserOptions: {
          project: 'tsconfig.json',
        },
      }),
    },

    rules: {
      '@typescript-eslint/interface-name-prefix': 'off',
      '@typescript-eslint/explicit-function-return-type': 'error',
      '@typescript-eslint/explicit-module-boundary-types': 'off',
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-empty-function': 'off',
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
        },
      ],
      'multiline-comment-style': ['error', 'starred-block'],
      'jsdoc/require-description': 'error',
      'custom-rules/no-consecutive-logging': 'error',
    },
  },
  {
    files: ['**/*.spec.ts', '**/*.test.ts'],
    rules: {
      '@typescript-eslint/explicit-function-return-type': 'off',
      '@typescript-eslint/no-unsafe-function-type': 'off',
    },
  },
];
