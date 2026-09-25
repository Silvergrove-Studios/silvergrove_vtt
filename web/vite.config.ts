import { defineConfig } from 'vitest/config';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// The web Table: built into dist/ and packed into ../webclient.zip
// (scripts/pack.mjs), which the Hexmap host serves (WebServer). One page;
// the path decides whose screen it is.
export default defineConfig({
  plugins: [svelte()],
  base: '/',
  build: { outDir: 'dist', emptyOutDir: true, assetsDir: 'assets', sourcemap: false, chunkSizeWarningLimit: 2000 },
  test: { environment: 'node', include: ['tests/**/*.test.ts'] },
});
