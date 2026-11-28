import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const FONT_STYLESHEET_URL =
  'https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:ital,wght@0,400;0,500;0,600;0,700;1,400&display=swap';

const config: Config = {
  title: 'Taurus',
  tagline: 'A wayland shell built for you',
  favicon: 'favicon.ico',

  future: {
    v4: true,
  },

  url: 'https://0x0ar.github.io',
  baseUrl: '/taurus/',
  trailingSlash: false,

  organizationName: '0x0ar',
  projectName: 'taurus',

  onBrokenLinks: 'throw',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  headTags: [
    {
      tagName: 'link',
      attributes: {rel: 'preconnect', href: 'https://fonts.googleapis.com'},
    },
    {
      tagName: 'link',
      attributes: {rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: 'anonymous'},
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'preload',
        as: 'style',
        href: FONT_STYLESHEET_URL,
      },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'stylesheet',
        href: FONT_STYLESHEET_URL,
        media: 'print',
        onload: "this.onload=null;this.media='all'",
      },
    },
    {
      tagName: 'noscript',
      attributes: {},
      innerHTML: `<link rel="stylesheet" href="${FONT_STYLESHEET_URL}" />`,
    },
    {
      tagName: 'link',
      attributes: {rel: 'icon', href: '/favicon-48.png', type: 'image/png', sizes: '48x48'},
    },
    {
      tagName: 'link',
      attributes: {rel: 'icon', href: '/favicon-192.png', type: 'image/png', sizes: '192x192'},
    },
    {
      tagName: 'link',
      attributes: {rel: 'apple-touch-icon', href: '/apple-touch-icon.png'},
    },
  ],

  themes: [
    [
      require.resolve('@easyops-cn/docusaurus-search-local'),
      {
        hashed: true,
        docsRouteBasePath: '/',
        docsDir: '../docs',
        indexBlog: false,
        searchBarShortcutHint: false,
        highlightSearchTermsOnTargetPage: false,
        explicitSearchResultPath: true,
      },
    ],
  ],

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          routeBasePath: '/',
          path: '../docs',
          editUrl: 'https://github.com/0x0ar/taurus/edit/main/docs/',
        },
        blog: false,
        theme: {
          customCss: ['./src/css/custom.css', './src/css/docs.css'],
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/social-card.jpg',
    colorMode: {
      defaultMode: 'dark',
      respectPrefersColorScheme: false,
    },
    navbar: {
      title: 'Taurus',
      logo: {
        alt: 'Taurus Logo',
        src: 'img/logo-light.svg',
        srcDark: 'img/logo-dark.svg',
        width: 32,
        height: 32,
      },
      items: [
        {
          to: '/overview',
          label: 'Documentation',
          position: 'left',
        },
        {
          href: 'https://github.com/0x0ar/taurus/blob/main/CHANGELOG.md',
          label: 'Changelog',
          position: 'left',
          className: 'navbar-changelog-link',
        },
        {
          type: 'search',
          position: 'right',
        },
        {
          href: 'https://github.com/0x0ar/taurus',
          label: 'GitHub',
          position: 'right',
          className: 'navbar-github-link',
          'aria-label': 'GitHub repository',
        },
        {
          href: 'https://www.reddit.com/r/taurus',
          label: 'Reddit',
          position: 'right',
          className: 'navbar-reddit-link',
          'aria-label': 'Reddit community',
        },
      ],
    },
    footer: {
      style: 'dark',
      logo: {
        alt: 'Taurus Logo',
        src: 'img/logo-light.svg',
        srcDark: 'img/logo-dark.svg',
        width: 44,
        height: 44,
      },
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'Overview',
              to: '/overview',
            },
            {
              label: 'Installation',
              to: '/installation',
            },
            {
              label: 'Variables',
              to: '/configure',
            },
          ],
        },
        {
          title: 'Community',
          items: [
            {
              label: 'GitHub',
              href: 'https://github.com/0x0ar/taurus',
            },
          ],
        },
      ],
      copyright: `A desktop shell built for YOU. Copyright © ${new Date().getFullYear()} Taurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['bash', 'ini', 'json', 'lua', 'nix'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
