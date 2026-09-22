import js from '@eslint/js';
import ts from 'typescript-eslint';
import globals from 'globals';
import { defineConfig } from 'eslint/config';
export default defineConfig(
  {
    ignores: [
      'dist/**',
      '.astro/**',
      'node_modules/**',
      '.artifacts/**',
      'playwright-report/**',
      'test-results/**',
      '**/.terraform/**',
    ],
  },
  js.configs.recommended,
  ...ts.configs.recommended,
  { languageOptions: { globals: { ...globals.browser, ...globals.node } } },
);
