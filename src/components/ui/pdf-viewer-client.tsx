'use client'

import { useEffect, useRef, useState } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import 'react-pdf/dist/Page/AnnotationLayer.css';
import 'react-pdf/dist/Page/TextLayer.css';
import { ChevronLeft, ChevronRight, ZoomIn, ZoomOut, MessageSquarePlus, PanelTop, RotateCw } from 'lucide-react';
import { Button } from './button';

// Configure the worker for pdf.js
pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  'pdfjs-dist/build/pdf.worker.min.mjs',
  import.meta.url,
).toString();

type PdfViewerProps = {
  url: string
  /** One-based source-locator page. It is clamped when the PDF reports its length. */
  initialPage?: number
}

function clampPage(page: number, numPages?: number) {
  const integerPage = Number.isFinite(page) ? Math.trunc(page) : 1
  const lowerBounded = Math.max(1, integerPage)
  return numPages ? Math.min(numPages, lowerBounded) : lowerBounded
}

export function PdfViewer({ url, initialPage = 1 }: PdfViewerProps) {
  const [numPages, setNumPages] = useState<number>();
  const [pageNumber, setPageNumber] = useState<number>(() => clampPage(initialPage));
  const [scale, setScale] = useState<number>(1.0);
  const [fitWidth, setFitWidth] = useState(true);
  const [rotation, setRotation] = useState(0);
  const [pageWidth, setPageWidth] = useState<number>();
  const [renderedSource, setRenderedSource] = useState({ url, initialPage });
  const scrollContainerRef = useRef<HTMLDivElement>(null);

  const [selection, setSelection] = useState<{ text: string, x: number, y: number } | null>(null);

  // Listen for jump events from the notes panel
  useEffect(() => {
    const handleJump = (e: CustomEvent) => {
      if (e.detail && typeof e.detail.pageNumber === 'number') {
        setPageNumber(clampPage(e.detail.pageNumber, numPages));
      }
    };
    window.addEventListener('JUMP_TO_PDF_PAGE', handleJump as EventListener);
    return () => window.removeEventListener('JUMP_TO_PDF_PAGE', handleJump as EventListener);
  }, [numPages]);

  if (renderedSource.url !== url || renderedSource.initialPage !== initialPage) {
    setRenderedSource({ url, initialPage });
    setNumPages(undefined);
    setPageNumber(clampPage(initialPage));
    setScale(1);
    setFitWidth(true);
    setRotation(0);
    setSelection(null);
  }

  useEffect(() => {
    const container = scrollContainerRef.current;
    if (!container) return;

    const updateWidth = () => {
      const horizontalPadding = window.innerWidth < 640 ? 16 : 32;
      setPageWidth(Math.max(1, container.clientWidth - horizontalPadding));
    };
    updateWidth();
    const observer = new ResizeObserver(updateWidth);
    observer.observe(container);
    return () => observer.disconnect();
  }, []);

  function onDocumentLoadSuccess({ numPages }: { numPages: number }): void {
    setNumPages(numPages);
    setPageNumber(page => clampPage(page, numPages));
  }

  function previousPage() {
    setPageNumber(page => Math.max(1, page - 1));
  }

  function nextPage() {
    setPageNumber(page => Math.min(numPages || 1, page + 1));
  }

  function handleViewerKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    const target = event.target as HTMLElement;
    if (target.closest('button, input, select, textarea, a, [contenteditable="true"]')) return;

    if (event.key === 'ArrowLeft' || event.key === 'PageUp') {
      event.preventDefault();
      previousPage();
    } else if (event.key === 'ArrowRight' || event.key === 'PageDown') {
      event.preventDefault();
      nextPage();
    } else if (event.key === 'Home') {
      event.preventDefault();
      setPageNumber(1);
    } else if (event.key === 'End' && numPages) {
      event.preventDefault();
      setPageNumber(numPages);
    }
  }

  const handleMouseUp = (e: React.MouseEvent) => {
    const text = window.getSelection()?.toString().trim();
    if (text && text.length > 0) {
      // Calculate position for the floating button (relative to viewport)
      setSelection({
        text,
        x: e.clientX,
        y: e.clientY
      });
    } else {
      setSelection(null);
    }
  };

  const handleAddNoteClick = () => {
    if (selection) {
      // Dispatch event to the Sidebar
      window.dispatchEvent(new CustomEvent('SET_PDF_QUOTE', {
        detail: {
          quote: selection.text,
          pageNumber: pageNumber
        }
      }));
      setSelection(null);
      window.getSelection()?.removeAllRanges();
    }
  };

  return (
    <div className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-[var(--surface)]">
      {/* Toolbar */}
      <div className="z-10 flex min-h-14 w-full shrink-0 flex-wrap items-center justify-center gap-1 border-b border-[var(--border)] bg-[var(--surface)] p-2 sm:gap-2">
        <Button variant="ghost" size="icon" className="min-h-11 min-w-11" aria-label="Previous page" title="Previous page" onClick={previousPage} disabled={pageNumber <= 1}>
          <ChevronLeft size={16} />
        </Button>
        <label className="flex min-h-11 items-center gap-1 text-sm font-medium text-[var(--text-primary)]">
          <span className="sr-only">Current PDF page</span>
          <input
            type="number"
            min={1}
            max={numPages}
            value={pageNumber}
            onChange={event => setPageNumber(clampPage(Number(event.target.value) || 1, numPages))}
            className="h-9 w-14 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-2 text-center text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
          />
          <span className="whitespace-nowrap text-[var(--text-muted)]">of {numPages || '--'}</span>
        </label>
        <Button variant="ghost" size="icon" className="min-h-11 min-w-11" aria-label="Next page" title="Next page" onClick={nextPage} disabled={pageNumber >= (numPages || 1)}>
          <ChevronRight size={16} />
        </Button>

        <div className="mx-1 hidden h-6 w-px bg-[var(--border)] sm:block" />

        <Button variant="ghost" size="icon" className="min-h-11 min-w-11" aria-label="Zoom out" title="Zoom out" onClick={() => { setFitWidth(false); setScale(s => Math.max(0.5, s - 0.2)); }}>
          <ZoomOut size={16} />
        </Button>
        <span className="w-12 text-center text-sm font-medium text-[var(--text-primary)]">
          {fitWidth ? 'Fit' : `${Math.round(scale * 100)}%`}
        </span>
        <Button variant="ghost" size="icon" className="min-h-11 min-w-11" aria-label="Zoom in" title="Zoom in" onClick={() => { setFitWidth(false); setScale(s => Math.min(3, s + 0.2)); }}>
          <ZoomIn size={16} />
        </Button>
        <Button type="button" variant="outline" className="min-h-11" onClick={() => setFitWidth(true)} aria-pressed={fitWidth}>
          <PanelTop size={16} aria-hidden="true" />
          Fit width
        </Button>
        <Button
          type="button"
          variant="outline"
          className="min-h-11"
          onClick={() => setRotation(current => (current + 90) % 360)}
          aria-label={`Rotate PDF clockwise. Current rotation ${rotation} degrees`}
          title={`Current rotation: ${rotation}°`}
        >
          <RotateCw size={16} aria-hidden="true" />
          Rotate
        </Button>
      </div>

      {/* PDF Container */}
      <div 
        ref={scrollContainerRef}
        tabIndex={0}
        role="region"
        aria-label="PDF page viewer"
        aria-keyshortcuts="ArrowLeft ArrowRight PageUp PageDown Home End"
        className="custom-scrollbar relative flex min-h-0 w-full flex-1 justify-center overflow-auto bg-[var(--bg-overlay)] p-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)] sm:p-4"
        onMouseUp={handleMouseUp}
        onKeyDown={handleViewerKeyDown}
      >
        <Document 
          file={url} 
          onLoadSuccess={onDocumentLoadSuccess} 
          loading={<div className="p-10 font-medium text-[var(--text-muted)] animate-pulse">Loading PDF Document...</div>}
          error={<div className="p-10 font-medium text-[var(--danger)]">Failed to load PDF. Please try again later.</div>}
        >
          <Page 
            pageNumber={pageNumber} 
            width={fitWidth ? pageWidth : undefined}
            scale={fitWidth ? undefined : scale}
            rotate={rotation}
            className="shadow-[var(--shadow-lg)]"
            renderTextLayer={true}
            renderAnnotationLayer={true}
          />
        </Document>

        {/* Floating Add Note Button */}
        {selection && (
          <div 
            style={{ position: 'fixed', top: selection.y - 45, left: selection.x - 20, zIndex: 50 }}
            className="animate-fade-in"
          >
            <Button 
              size="sm" 
              onClick={handleAddNoteClick}
              className="bg-[--primary] hover:bg-[--primary-hover] text-white shadow-xl rounded-full px-3 py-1.5 flex items-center gap-1.5 h-auto text-xs"
            >
              <MessageSquarePlus size={14} /> Add Note
            </Button>
          </div>
        )}
      </div>
    </div>
  );
}
