import React from 'react';
import MDXComponents from '@theme-original/MDXComponents';
import ThemedBanner from '@site/src/components/ThemedBanner';

export default {
  ...MDXComponents,
  img: (props: React.ComponentProps<'img'>) => {
    if (props.alt === 'Taurus Banner') {
      return <ThemedBanner alt={props.alt} />;
    }
    return <img {...props} />;
  },
};
