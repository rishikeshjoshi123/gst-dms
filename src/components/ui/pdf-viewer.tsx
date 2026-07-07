'use client'

import dynamic from 'next/dynamic';

export const PdfViewer = dynamic(
  () => import('./pdf-viewer-client').then((mod) => mod.PdfViewer),
  { ssr: false, loading: () => <div className="flex h-full items-center justify-center text-[var(--text-muted)] animate-pulse">Loading PDF Viewer...</div> }
);
