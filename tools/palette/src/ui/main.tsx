import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { PaletteApp } from './PaletteApp.tsx';
import './styles.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <PaletteApp />
  </StrictMode>,
);
