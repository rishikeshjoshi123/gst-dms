'use client'

import { useEffect, useRef, useState } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import 'react-pdf/dist/Page/AnnotationLayer.css';
import 'react-pdf/dist/Page/TextLayer.css';
import { ChevronLeft, ChevronRight, ZoomIn, ZoomOut, MessageSquarePlus, PanelTop, RotateCw } from 'lucide-react';
import { Button } from './button';
import {
  clampPdfPage,
  isPdfPageInRenderWindow,
  pdfPageHeight,
} from './pdf-viewer-model';

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

export function PdfViewer({ url, initialPage = 1 }: PdfViewerProps) {
  const [numPages, setNumPages] = useState<number>();
  const [pageNumber, setPageNumber] = useState<number>(() => clampPdfPage(initialPage));
  const [scale, setScale] = useState<number>(1.0);
  const [fitWidth, setFitWidth] = useState(true);
  const [rotation, setRotation] = useState(0);
  const [pageWidth, setPageWidth] = useState<number>();
  const [pageSizes, setPageSizes] = useState<Record<number, { width: number; height: number }>>({});
  const [renderedSource, setRenderedSource] = useState({ url, initialPage });
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const pageElementsRef = useRef(new Map<number, HTMLElement>());
  const shouldScrollToPageRef = useRef(true);

  const [selection, setSelection] = useState<{ text: string, x: number, y: number, pageNumber: number } | null>(null);

  function scrollPageIntoView(page: number) {
    const container = scrollContainerRef.current;
    const element = pageElementsRef.current.get(page);
    if (!container || !element) return;
    container.scrollTo({ top: Math.max(0, element.offsetTop - 16) });
  }

  // Listen for jump events from the notes panel
  useEffect(() => {
    const handleJump = (e: CustomEvent) => {
      if (e.detail && typeof e.detail.pageNumber === 'number') {
        const nextPage = clampPdfPage(e.detail.pageNumber, numPages);
        shouldScrollToPageRef.current = true;
        setPageNumber(nextPage);
        window.requestAnimationFrame(() => {
          scrollPageIntoView(nextPage);
          shouldScrollToPageRef.current = false;
        });
      }
    };
    window.addEventListener('JUMP_TO_PDF_PAGE', handleJump as EventListener);
    return () => window.removeEventListener('JUMP_TO_PDF_PAGE', handleJump as EventListener);
  }, [numPages]);

  if (renderedSource.url !== url || renderedSource.initialPage !== initialPage) {
    setRenderedSource({ url, initialPage });
    setNumPages(undefined);
    setPageNumber(clampPdfPage(initialPage));
    setScale(1);
    setFitWidth(true);
    setRotation(0);
    setPageSizes({});
    setSelection(null);
  }

  useEffect(() => {
    pageElementsRef.current.clear();
    shouldScrollToPageRef.current = true;
  }, [renderedSource]);

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
    setPageNumber(page => {
      shouldScrollToPageRef.current = true;
      return clampPdfPage(page, numPages);
    });
  }

  useEffect(() => {
    if (!numPages || !shouldScrollToPageRef.current) return;
    const frame = window.requestAnimationFrame(() => {
      scrollPageIntoView(pageNumber);
      shouldScrollToPageRef.current = false;
    });
    return () => window.cancelAnimationFrame(frame);
  }, [numPages, pageNumber]);

  useEffect(() => {
    const container = scrollContainerRef.current;
    if (!container || !numPages) return;
    const visibility = new Map<number, number>();
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        const page = Number((entry.target as HTMLElement).dataset.pdfPage);
        if (Number.isSafeInteger(page)) visibility.set(page, entry.intersectionRatio);
      }
      if (shouldScrollToPageRef.current) return;
      const visiblePage = Array.from(visibility.entries())
        .filter(([, ratio]) => ratio > 0)
        .sort((left, right) => right[1] - left[1] || left[0] - right[0])[0]?.[0];
      if (visiblePage) setPageNumber(current => current === visiblePage ? current : visiblePage);
    }, { root: container, threshold: [0, 0.15, 0.35, 0.6, 0.85] });

    for (const element of pageElementsRef.current.values()) observer.observe(element);
    return () => observer.disconnect();
  }, [numPages]);

  function requestPage(page: number) {
    const nextPage = clampPdfPage(page, numPages);
    shouldScrollToPageRef.current = true;
    setPageNumber(nextPage);
    window.requestAnimationFrame(() => {
      scrollPageIntoView(nextPage);
      shouldScrollToPageRef.current = false;
    });
  }

  function preserveCurrentPageAfterLayout() {
    shouldScrollToPageRef.current = true;
    window.requestAnimationFrame(() => {
      scrollPageIntoView(pageNumber);
      shouldScrollToPageRef.current = false;
    });
  }

  function zoomBy(delta: number) {
    setFitWidth(false);
    setScale(current => Math.min(3, Math.max(0.5, current + delta)));
    preserveCurrentPageAfterLayout();
  }

  function fitPageWidth() {
    setFitWidth(true);
    preserveCurrentPageAfterLayout();
  }

  function rotateClockwise() {
    setRotation(current => (current + 90) % 360);
    preserveCurrentPageAfterLayout();
  }

  function recordPageSize(page: number, proxy: { getViewport: (options: { scale: number }) => { width: number; height: number } }) {
    const viewport = proxy.getViewport({ scale: 1 });
    setPageSizes(current => {
      const existing = current[page];
      if (existing?.width === viewport.width && existing.height === viewport.height) return current;
      return { ...current, [page]: { width: viewport.width, height: viewport.height } };
    });
  }

  function pageHeight(page: number) {
    return pdfPageHeight({ sourceSize: pageSizes[page], rotation, fitWidth, pageWidth, scale });
  }

  function previousPage() {
    requestPage(pageNumber - 1);
  }

  function nextPage() {
    requestPage(pageNumber + 1);
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
      requestPage(1);
    } else if (event.key === 'End' && numPages) {
      event.preventDefault();
      requestPage(numPages);
    }
  }

  const handleMouseUp = (e: React.MouseEvent) => {
    const text = window.getSelection()?.toString().trim();
    if (text && text.length > 0) {
      const pageElement = (e.target as HTMLElement).closest<HTMLElement>('[data-pdf-page]');
      const selectedPage = clampPdfPage(Number(pageElement?.dataset.pdfPage) || pageNumber, numPages);
      // Calculate position for the floating button (relative to viewport)
      setSelection({
        text,
        x: e.clientX,
        y: e.clientY,
        pageNumber: selectedPage,
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
          pageNumber: selection.pageNumber
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
            onChange={event => requestPage(Number(event.target.value) || 1)}
            className="h-9 w-14 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-2 text-center text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
          />
          <span className="whitespace-nowrap text-[var(--text-muted)]">of {numPages || '--'}</span>
        </label>
        <Button variant="ghost" size="icon" className="min-h-11 min-w-11" aria-label="Next page" title="Next page" onClick={nextPage} disabled={pageNumber >= (numPages || 1)}>
          <ChevronRight size={16} />
        </Button>

        <div className="mx-1 hidden h-6 w-px bg-[var(--border)] sm:block" />

        <Button variant="ghost" size="icon" className="min-h-11 min-w-11" aria-label="Zoom out" title="Zoom out" onClick={() => zoomBy(-0.2)}>
          <ZoomOut size={16} />
        </Button>
        <span className="w-12 text-center text-sm font-medium text-[var(--text-primary)]">
          {fitWidth ? 'Fit' : `${Math.round(scale * 100)}%`}
        </span>
        <Button variant="ghost" size="icon" className="min-h-11 min-w-11" aria-label="Zoom in" title="Zoom in" onClick={() => zoomBy(0.2)}>
          <ZoomIn size={16} />
        </Button>
        <Button type="button" variant="outline" className="min-h-11" onClick={fitPageWidth} aria-pressed={fitWidth}>
          <PanelTop size={16} aria-hidden="true" />
          Fit width
        </Button>
        <Button
          type="button"
          variant="outline"
          className="min-h-11"
          onClick={rotateClockwise}
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
          className="flex w-full flex-col items-center gap-4"
          loading={<div className="p-10 font-medium text-[var(--text-muted)] animate-pulse">Loading PDF Document...</div>}
          error={<div className="p-10 font-medium text-[var(--danger)]">Failed to load PDF. Please try again later.</div>}
        >
          {numPages && Array.from({ length: numPages }, (_, index) => {
            const page = index + 1;
            const shouldRender = isPdfPageInRenderWindow(page, pageNumber);
            const estimatedHeight = pageHeight(page);
            return (
              <div
                key={page}
                ref={(element) => {
                  if (element) pageElementsRef.current.set(page, element);
                  else pageElementsRef.current.delete(page);
                }}
                data-pdf-page={page}
                aria-label={`PDF page ${page} of ${numPages}`}
                className="flex w-full shrink-0 scroll-mt-4 justify-center"
                style={{ minHeight: estimatedHeight }}
              >
                {shouldRender ? (
                  <Page
                    pageNumber={page}
                    width={fitWidth ? pageWidth : undefined}
                    scale={fitWidth ? undefined : scale}
                    rotate={rotation}
                    onLoadSuccess={(proxy) => recordPageSize(page, proxy)}
                    className="shadow-[var(--shadow-lg)]"
                    renderTextLayer={true}
                    renderAnnotationLayer={true}
                  />
                ) : (
                  <div
                    aria-hidden="true"
                    className="w-full max-w-full bg-[var(--surface)] shadow-[var(--shadow-sm)]"
                    style={{ height: estimatedHeight, maxWidth: fitWidth ? pageWidth : undefined }}
                  />
                )}
              </div>
            );
          })}
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
