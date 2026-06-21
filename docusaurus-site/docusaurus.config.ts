import { themes as prismThemes } from "prism-react-renderer";
import type { Config } from "@docusaurus/types";
import type * as Preset from "@docusaurus/preset-classic";

// =======================================================================
// Docusaurus Configuration
// =======================================================================
// Deployed to GitLab Pages via .gitlab-ci.yml on every push to main.
//
// Before publishing, update:
//   url     → your GitLab Pages base domain (e.g. http://pages.lab.local)
//   baseUrl → /<namespace>/<project>/  (e.g. /yannick/docs/)
// =======================================================================

const config: Config = {
  title: "Lab Docs",
  tagline: "Knowledge base for the ProxmoxInfra home lab",
  favicon: "img/favicon.ico",

  // Update these two values to match your GitLab Pages URL
  url: "http://pages.lab.local",
  baseUrl: "/lab/docs/",

  // Fail build on broken links and anchors (enforces doc hygiene in CI)
  onBrokenLinks: "throw",
  onBrokenMarkdownLinks: "warn",

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
          // Enable "Edit this page" links pointing to the GitLab project
          // editUrl: "http://10.10.10.73/lab/docs/-/edit/main/",
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
        {
          href: "http://10.10.10.73",
          label: "GitLab",
          position: "right",
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
            { label: "GitLab", href: "http://10.10.10.73" },
            { label: "Paperless", href: "http://10.10.10.72:8000" },
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
  },

  themes: ["@docusaurus/theme-mermaid"],
};

export default config;
