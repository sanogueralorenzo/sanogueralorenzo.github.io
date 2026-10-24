/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  helpSidebar: [
    'index',
    {
      type: 'category',
      label: 'Get started',
      collapsed: false,
      items: [
        'getting-started/install-and-update-mac',
        'getting-started/move-to-crest',
        'getting-started/settings-reference',
        'browsing/engines',
      ],
    },
    {
      type: 'category',
      label: 'Spaces & organization',
      collapsed: false,
      items: [
        'spaces/spaces-and-isolation',
        'spaces/customize-spaces',
        'tabs/organize-tabs-and-folders',
        'tabs/split-view',
        'spaces/private-spaces',
        'spaces/sync-across-devices',
        'spaces/crest-passwords',
      ],
    },
    {
      type: 'category',
      label: 'Browse faster',
      collapsed: false,
      items: [
        'browsing/command-palette',
        'browsing/keyboard-shortcuts',
        'browsing/gestures-and-pointer',
        'browsing/peek-and-quick-window',
        'browsing/link-routing',
        'browsing/page-tools',
        'browsing/localhost-developer-tools',
        'browsing/coding-agents',
      ],
    },
    {
      type: 'category',
      label: 'Privacy, data & recovery',
      collapsed: false,
      items: [
        'privacy/content-blocking-and-site-permissions',
        'privacy/history-archive-and-downloads',
      ],
    },
    {
      type: 'category',
      label: 'Install extensions',
      collapsed: false,
      items: [
        'extensions/install-chrome-web-store',
        'extensions/install-firefox-add-ons',
        'extensions/scan-safari-web-extensions',
      ],
    },
    {
      type: 'category',
      label: 'Use extensions',
      collapsed: false,
      items: [
        'extensions/manage-permissions-site-access',
        'extensions/pin-and-use-popups',
        'extensions/keyboard-shortcuts',
      ],
    },
    {
      type: 'category',
      label: 'Compatibility & troubleshooting',
      collapsed: false,
      items: [
        'extensions/status-and-technical-details',
        'extensions/native-companion-limits',
        'extensions/api-compatibility-matrix',
        'extensions/compatibility',
        'extensions/troubleshoot-partial-compatibility',
        'extensions/onepassword',
        'extensions/icloud-passwords',
      ],
    },
  ],
};

module.exports = sidebars;
