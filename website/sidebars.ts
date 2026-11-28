import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  tutorialSidebar: [
    'Overview',
    'installation/installation',
    {
      type: 'category',
      label: 'Configure',
      collapsible: false,
      items: [
        'configure/Configure',
        'configure/Scenes',
        'configure/Recovery',
        'configure/Share',
        {
          type: 'category',
          label: 'Compositors',
          collapsible: false,
          items: [
            'configure/compositors/hyprland',
            'configure/compositors/niri',
            'configure/compositors/sway',
            'configure/compositors/mango',
            'configure/compositors/umbriel',
          ],
        },
      ],
    },
    {
      type: 'category',
      label: 'AI',
      collapsible: false,
      items: [
        'ai/agents',
      ],
    },
    {
      type: 'category',
      label: 'Components',
      collapsible: false,
      items: [
        'components/taurus-audio',
        'components/taurus-core',
        'components/taurus-gamma',
      ],
    },
    {
      type: 'category',
      label: 'CLI',
      collapsible: false,
      items: [
        'cli/client',
        'cli/daemon',
      ],
    },
  ],
};

export default sidebars;
