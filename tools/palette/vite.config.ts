import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  root: 'src/ui',
  base: './',
  build: {
    outDir: '../../dist/ui',
    emptyOutDir: true,
  },
});
