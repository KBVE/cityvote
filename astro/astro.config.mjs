// @ts-check
import { defineConfig } from "astro/config";
import worker from "@astropub/worker";

import starlight from "@astrojs/starlight";
import starlightThemeGalaxy from "starlight-theme-galaxy";
import tailwindcss from "@tailwindcss/vite";

import react from "@astrojs/react";

// https://astro.build/config
export default defineConfig({
  output: "static",

  integrations: [
    worker(),
    starlight({
      plugins: [starlightThemeGalaxy()],
      title: "BugWars",
      defaultLocale: "root",
      locales: {
        root: {
          label: "English",
          lang: "en",
        },
        es: {
          label: "Español",
          lang: "es",
        },
        ja: {
          label: "日本語",
          lang: "ja",
        },
        ko: {
          label: "한국어",
          lang: "ko",
        },
      },
      customCss: [
        // Path to your custom CSS file with cascade layers and purple theme
        "./src/styles/global.css",
      ],
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/withastro/starlight",
        },
      ],
      sidebar: [
        {
          label: "Dev Blog",
          autogenerate: { directory: "blog" },
        },
        {
          label: "Guides",
          autogenerate: { directory: "guides" },
        },
        {
          label: "Reference",
          autogenerate: { directory: "reference" },
        },
      ],
      components: {
        SiteTitle: "./src/components/navigation/SiteTitle.astro",
      },
    }),
    react(),
  ],

  vite: {
    plugins: [tailwindcss()],
    build: {
      rollupOptions: {
        external: ['fsevents', /^\.\.\/pkg/],
      },
    },
    optimizeDeps: {
      exclude: ['fsevents'],
    },
  },
});
