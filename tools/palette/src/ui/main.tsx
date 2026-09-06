import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { PaletteApp } from './PaletteApp.tsx';
import { createWebViewBridge } from './webview-bridge.ts';
import './styles.css';
import { createPreviewBridge } from './preview-bridge.ts';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <PaletteApp bridge={import.meta.env.DEV && new URLSearchParams(location.search).has('preview') ? createPreviewBridge() : createWebViewBridge()} />
  </StrictMode>,
);
