import { defineConfig } from 'astro/config';

export default defineConfig({
  srcDir: './app/src',
  publicDir: './app/public',
  output: 'static',
  build: { inlineStylesheets: 'never' },
  vite: { build: { assetsInlineLimit: 0 } },
});
