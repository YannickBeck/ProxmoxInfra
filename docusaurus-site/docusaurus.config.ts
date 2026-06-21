import { themes as prismThemes } from "prism-react-renderer";
import type { Config } from "@docusaurus/types";
import type * as Preset from "@docusaurus/preset-classic";

// =======================================================================
// Docusaurus Configuration
// =======================================================================
// Built as a container and served by the dedicated lab-docusaurus01 VM.
// =======================================================================

const config: Config = {
  title: "Lab Docs",
  tagline: "Knowledge base for the ProxmoxInfra home lab",
  favicon: "img/favicon.ico",

  url: "http://10.10.10.74",
  baseUrl: "/",

  // Fail build on broken links and anchors (enforces doc hygiene in CI)
  onBrokenLinks: "throw",

  i18n: {
    defaultLocale: "de",
    locales: ["de", "en"],
  },

  presets: [
    [
      "classic",
      {
        docs: {
          sidebarPath: "./sidebars.ts",
          showLastUpdateAuthor: true,
          showLastUpdateTime: true,
        },
        blog: false,
        theme: {
          customCss: "./src/css/custom.css",
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    navbar: {
      title: "Lab Docs",
      logo: {
        alt: "Lab Logo",
        src: "img/logo.svg",
      },
      items: [
        {
          type: "docSidebar",
          sidebarId: "mainSidebar",
          position: "left",
          label: "Dokumentation",
        },
      ],
    },
    footer: {
      style: "dark",
      links: [
        {
          title: "Docs",
          items: [
            { label: "Einführung", to: "/docs/intro" },
            { label: "Architektur", to: "/docs/architecture/overview" },
            { label: "Runbooks", to: "/docs/runbooks/" },
          ],
        },
        {
          title: "Lab Services",
          items: [
            { label: "TrueNAS", href: "http://10.10.10.70" },
            { label: "Proxmox", href: "https://192.168.1.100:8006" },
          ],
        },
      ],
      copyright: `© ${new Date().getFullYear()} Lab Docs. Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ["bash", "powershell", "yaml", "hcl", "docker"],
    },
    // Enable Mermaid diagrams in Markdown
    mermaid: {
      theme: { light: "neutral", dark: "forest" },
    },
  } satisfies Preset.ThemeConfig,

  markdown: {
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: "warn",
    },
  },

  themes: ["@docusaurus/theme-mermaid"],
};

export default config;
