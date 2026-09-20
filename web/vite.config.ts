/// <reference types="vitest" />
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // The API is a separate deployable, but in development it is served under
    // this origin so the browser never makes a cross-origin request at all.
    // That keeps CORS out of the local setup, and it means the dev build calls
    // the same relative paths the production build does — one code path rather
    // than a branch on the environment.
    //
    // The target is configurable because 3000 is the port every Rails app
    // wants, and a machine running more than one of them will need to move.
    proxy: {
      "/api": {
        target: process.env["API_PROXY_TARGET"] ?? "http://localhost:3000",
        changeOrigin: true,
      },
    },
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: "./src/setup-tests.ts",
    // Stylesheets are not asserted on, and parsing them for every test file is
    // the slowest thing in an otherwise sub-second suite.
    css: false,
  },
});
