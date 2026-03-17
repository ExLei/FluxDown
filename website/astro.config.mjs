// @ts-check
import { defineConfig } from "astro/config";

import react from "@astrojs/react";
import sitemap from "@astrojs/sitemap";
import tailwindcss from "@tailwindcss/vite";
import node from "@astrojs/node";

// https://astro.build/config
export default defineConfig({
  site: "https://fluxdown.zerx.dev",
  adapter: node({ mode: "standalone" }),
  integrations: [react(), sitemap()],

  vite: {
    plugins: [tailwindcss()],
  },
});
