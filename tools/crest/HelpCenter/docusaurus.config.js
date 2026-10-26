const {themes: prismThemes} = require('prism-react-renderer');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Crest Help',
  tagline: 'Help articles for Crest.',
  favicon: 'img/crest-logo.svg',
  url: 'https://crestbrowser.com',
  baseUrl: '/guides/',
  organizationName: 'pauljoda',
  projectName: 'Crest-Website',
  trailingSlash: true,
  onBrokenLinks: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },
  plugins: [require.resolve('./plugins/help-search-index')],
  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: require.resolve('./sidebars.js'),
          breadcrumbs: true,
          showLastUpdateAuthor: false,
          showLastUpdateTime: false,
        },
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
        sitemap: {
          changefreq: 'weekly',
          priority: 0.7,
        },
      },
    ],
  ],
  themeConfig: {
    image: 'https://crestbrowser.com/assets/og-card-brand.jpg',
    metadata: [
      {
        name: 'description',
        content: 'Help articles for Crest on Mac, iPad, and iPhone.',
      },
    ],
    colorMode: {
      defaultMode: 'light',
      disableSwitch: true,
      respectPrefersColorScheme: false,
    },
    navbar: {
      title: 'Crest Help',
      logo: {
        alt: 'Crest',
        src: 'img/crest-logo.svg',
      },
      items: [
        {type: 'docSidebar', sidebarId: 'helpSidebar', position: 'left', label: 'Articles'},
        {to: '/keyboard-shortcuts/', label: 'Shortcuts', position: 'left'},
        {to: '/extension-api-compatibility/', label: 'Compatibility', position: 'left'},
        {href: 'https://github.com/pauljoda/Crest/releases/latest', label: 'Download for Mac', position: 'right'},
        {href: 'https://crestbrowser.com/support/', label: 'Support', position: 'right'},
        {href: 'https://crestbrowser.com/', label: 'Product site', position: 'right'},
      ],
    },
    docs: {
      sidebar: {
        hideable: true,
        autoCollapseCategories: false,
      },
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Crest',
          items: [
            {label: 'Product site', href: 'https://crestbrowser.com/'},
            {label: 'Download for Mac', href: 'https://github.com/pauljoda/Crest/releases/latest'},
            {label: 'iPhone & iPad TestFlight', href: 'https://testflight.apple.com/join/vV1CM49Q'},
          ],
        },
        {
          title: 'Help',
          items: [
            {label: 'All articles', to: '/'},
            {label: 'Keyboard shortcuts', to: '/keyboard-shortcuts/'},
            {label: 'Split View', to: '/split-view/'},
            {label: 'Extension compatibility', to: '/extension-api-compatibility/'},
            {label: 'Support', href: 'https://crestbrowser.com/support/'},
          ],
        },
        {
          title: 'Community',
          items: [
            {label: 'GitHub Issues', href: 'https://github.com/pauljoda/Crest/issues/new/choose'},
            {label: 'r/CrestBrowser', href: 'https://www.reddit.com/r/CrestBrowser'},
            {label: 'Discord', href: 'https://discord.gg/gjrM5qMB6x'},
            {label: 'Support open source software', href: 'https://ko-fi.com/pauljoda/tiers'},
            {label: 'Privacy', href: 'https://crestbrowser.com/privacy/'},
          ],
        },
      ],
      copyright: `Crest is not affiliated with Arc. © ${new Date().getFullYear()} Paul Davis.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  },
};

module.exports = config;
