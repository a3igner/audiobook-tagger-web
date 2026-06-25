import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// VITE_BASE_PATH controls the asset URL prefix. Override at build time:
//
//   docker build --build-arg VITE_BASE_PATH=/tagger/   # for sub-path hosting
//   docker build                                       # default = "/" (root hosting)
//
// With VITE_BASE_PATH="/tagger/", Vite injects <base href="/tagger/"> into
// index.html and rewrites all asset URLs (e.g. /assets/index-XYZ.js →
// /tagger/assets/index-XYZ.js) so the browser resolves them against the
// Caddy reverse-proxied path. Leave it at "/" if you serve the SPA at the
// web root (e.g. http://localhost:8082/ or http://tagger.example.com/).
const basePath = process.env.VITE_BASE_PATH || "/";

export default defineConfig({
  base: basePath,
  plugins: [react()],
  server: {
    port: 3000,
  },
  build: {
    target: ["es2021", "chrome100", "firefox100", "safari15"],
    minify: "esbuild",
    sourcemap: false,
    outDir: "dist",
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom'],
          icons: ['lucide-react'],
        },
      },
    },
  },
});
