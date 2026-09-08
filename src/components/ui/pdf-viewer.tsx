'use client'

import dynamic from 'next/dynamic';

export type { PdfQuotationSelection, PdfQuoteSource } from './pdf-viewer-client';

export const PdfViewer = dynamic(
  () => import('./pdf-viewer-client').then((mod) => mod.PdfViewer),
  { ssr: false, loading: () => <div role="status" className="flex h-full animate-pulse items-center justify-center text-[var(--text-muted)] motion-reduce:animate-none">Loading PDF viewer…</div> }
);
