import React from 'react';

export default function GuideScreenshot({src, alt, caption}) {
  return (
    <figure className="guide-screenshot">
      <img src={src} alt={alt} loading="lazy" />
      {caption && <figcaption>{caption}</figcaption>}
    </figure>
  );
}
