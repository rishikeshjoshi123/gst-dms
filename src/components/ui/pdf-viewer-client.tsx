'use client'

import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Document, Page, pdfjs } from 'react-pdf';
import type { PDFDocumentProxy } from 'pdfjs-dist';
import 'react-pdf/dist/Page/AnnotationLayer.css';
import 'react-pdf/dist/Page/TextLayer.css';
import { ChevronLeft, ChevronRight, FileText, ZoomIn, ZoomOut, MessageSquarePlus, PanelLeft, PanelTop, RefreshCw, RotateCw, Search, X } from 'lucide-react';
import { Button } from './button';
import { Input } from './input';
import {
  clampPdfPage,
  createPdfQuotationSelection,
  classifyPdfSourceFailure,
  highlightPdfText,
  isPdfPageInRenderWindow,
  isPdfSourceRequestCurrent,
  nextPdfSearchBatch,
  normalizePdfSearchQuery,
  PDF_SEARCH_BATCH_SIZE,
  pdfFitPageScale,
  pdfPageHeight,
  pdfThumbnailPages,
  pdfSourceFailureCopy,
  retryPdfSourceAccess,
  type PdfSourceFailure,
} from './pdf-viewer-model';

// Configure the worker for pdf.js
pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  'pdfjs-dist/build/pdf.worker.min.mjs',
  import.meta.url,
).toString();

type PdfViewerProps = {
  url: string | null
  /** One-based source-locator page. It is clamped when the PDF reports its length. */
  initialPage?: number
  initialFailure?: PdfSourceFailure
  onRequestSourceRefresh?: () => Promise<string | null>
  quoteSource?: PdfQuoteSource
  onCreateQuotation?: (selection: PdfQuotationSelection) => void
}

export type PdfQuoteSource = {
  documentId: string
  documentVersionId: string
}

export type PdfQuotationSelection = PdfQuoteSource & {
  text: string
  pageNumber: number
}

export function PdfViewer({
  url,
  initialPage = 1,
  initialFailure,
  onRequestSourceRefresh,
  quoteSource,
  onCreateQuotation,
}: PdfViewerProps) {
  const router = useRouter();
  const searchInputId = useId();
  const thumbnailStripId = useId();
  const [numPages, setNumPages] = useState<number>();
  const [pageNumber, setPageNumber] = useState<number>(() => clampPdfPage(initialPage));
  const [scale, setScale] = useState<number>(1.0);
  const [fitWidth, setFitWidth] = useState(true);
  const [fitPage, setFitPage] = useState(false);
  const [rotation, setRotation] = useState(0);
  const [pageWidth, setPageWidth] = useState<number>();
  const [pageViewportHeight, setPageViewportHeight] = useState<number>();
  const [pageSizes, setPageSizes] = useState<Record<number, { width: number; height: number }>>({});
  const [searchQuery, setSearchQuery] = useState('');
  const [activeSearchQuery, setActiveSearchQuery] = useState('');
  const [searchedPages, setSearchedPages] = useState(0);
  const [searchResults, setSearchResults] = useState<number[]>([]);
  const [activeSearchResult, setActiveSearchResult] = useState(-1);
  const [isSearchPending, setIsSearchPending] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [thumbnailsOpen, setThumbnailsOpen] = useState(false);
  const [sourceFailure, setSourceFailure] = useState<PdfSourceFailure | null>(() => initialFailure ?? (url ? null : 'unavailable'));
  const [activeUrl, setActiveUrl] = useState(url);
  const [isSourceRetryPending, setIsSourceRetryPending] = useState(false);
  const [sourceRetryError, setSourceRetryError] = useState<string | null>(null);
  const [documentAttempt, setDocumentAttempt] = useState(0);
  const [pageFailures, setPageFailures] = useState<Record<number, boolean>>({});
  const [pageAttempts, setPageAttempts] = useState<Record<number, number>>({});
  const sourceIdentity = quoteSource ? `${quoteSource.documentId}:${quoteSource.documentVersionId}` : null;
  const [renderedSource, setRenderedSource] = useState({ url, initialPage, initialFailure, sourceIdentity });
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const pageElementsRef = useRef(new Map<number, HTMLElement>());
  const shouldScrollToPageRef = useRef(true);
  const pdfDocumentRef = useRef<PDFDocumentProxy | null>(null);
  const searchGenerationRef = useRef(0);
  const thumbnailStripRef = useRef<HTMLDivElement>(null);
  const thumbnailElementsRef = useRef(new Map<number, HTMLButtonElement>());
  const sourceRequestGenerationRef = useRef(0);
  const sourceRequestCurrentRef = useRef({ generation: 0, sourceIdentity });

  const [selection, setSelection] = useState<{ text: string, x: number, y: number, pageNumber: number } | null>(null);

  function scrollPageIntoView(page: number) {
    const container = scrollContainerRef.current;
    const element = pageElementsRef.current.get(page);
    if (!container || !element) return;
    container.scrollTo({ top: Math.max(0, element.offsetTop - 16) });
  }

  if (renderedSource.url !== url || renderedSource.initialPage !== initialPage || renderedSource.initialFailure !== initialFailure || renderedSource.sourceIdentity !== sourceIdentity) {
    const urlChanged = renderedSource.url !== url;
    setRenderedSource({ url, initialPage, initialFailure, sourceIdentity });
    if (urlChanged) {
      setNumPages(undefined);
      setPageSizes({});
    }
    setPageNumber(clampPdfPage(initialPage));
    setScale(1);
    setFitWidth(true);
    setFitPage(false);
    setRotation(0);
    setSearchQuery('');
    setActiveSearchQuery('');
    setSearchedPages(0);
    setSearchResults([]);
    setActiveSearchResult(-1);
    setIsSearchPending(false);
    setSearchError(null);
    setThumbnailsOpen(false);
    setSourceFailure(initialFailure ?? (url ? null : 'unavailable'));
    setActiveUrl(url);
    setIsSourceRetryPending(false);
    setSourceRetryError(null);
    setDocumentAttempt(0);
    setPageFailures({});
    setPageAttempts({});
    setSelection(null);
  }

  useLayoutEffect(() => {
    sourceRequestGenerationRef.current += 1;
    sourceRequestCurrentRef.current = {
      generation: sourceRequestGenerationRef.current,
      sourceIdentity,
    };
  }, [sourceIdentity, url, initialPage, initialFailure]);

  useEffect(() => {
    shouldScrollToPageRef.current = true;
    searchGenerationRef.current += 1;
  }, [renderedSource]);

  useEffect(() => {
    pageElementsRef.current.clear();
    thumbnailElementsRef.current.clear();
    pdfDocumentRef.current = null;
  }, [renderedSource.url]);

  useEffect(() => {
    const container = scrollContainerRef.current;
    if (!container) return;

    const updateViewport = () => {
      const horizontalPadding = window.innerWidth < 640 ? 16 : 32;
      const verticalPadding = window.innerWidth < 640 ? 16 : 32;
      setPageWidth(Math.max(1, container.clientWidth - horizontalPadding));
      setPageViewportHeight(Math.max(1, container.clientHeight - verticalPadding));
    };
    updateViewport();
    const observer = new ResizeObserver(updateViewport);
    observer.observe(container);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (!fitWidth && !fitPage) return;
    shouldScrollToPageRef.current = true;
    const frame = window.requestAnimationFrame(() => {
      scrollPageIntoView(pageNumber);
      shouldScrollToPageRef.current = false;
    });
    return () => window.cancelAnimationFrame(frame);
  }, [fitPage, fitWidth, pageNumber, pageViewportHeight, pageWidth]);

  function onDocumentLoadSuccess(document: PDFDocumentProxy): void {
    setSourceFailure(null);
    pdfDocumentRef.current = document;
    setNumPages(document.numPages);
    setPageNumber(page => {
      shouldScrollToPageRef.current = true;
      return clampPdfPage(page, document.numPages);
    });
  }

  function presentSourceFailure(failure: PdfSourceFailure | null) {
    if (!failure) return;
    searchGenerationRef.current += 1;
    pdfDocumentRef.current = null;
    setNumPages(undefined);
    setIsSearchPending(false);
    setThumbnailsOpen(false);
    setSourceFailure(failure);
  }

  function onDocumentLoadError(error: unknown) {
    presentSourceFailure(classifyPdfSourceFailure(error));
  }

  function onDocumentSourceError(error: unknown) {
    if (classifyPdfSourceFailure(error) === null) return;
    presentSourceFailure('unavailable');
  }

  async function retrySource() {
    const requestGeneration = sourceRequestGenerationRef.current + 1;
    const requestedIdentity = sourceRequestCurrentRef.current.sourceIdentity;
    sourceRequestGenerationRef.current = requestGeneration;
    sourceRequestCurrentRef.current = { generation: requestGeneration, sourceIdentity: requestedIdentity };
    setIsSourceRetryPending(true);
    setSourceRetryError(null);
    try {
      const refreshedUrl = await retryPdfSourceAccess({
        currentUrl: activeUrl,
        requestFreshUrl: onRequestSourceRefresh,
        refreshRoute: router.refresh,
      });
      if (!isPdfSourceRequestCurrent(
        { generation: requestGeneration, sourceIdentity: requestedIdentity },
        sourceRequestCurrentRef.current,
      )) return;
      if (!refreshedUrl) {
        if (onRequestSourceRefresh) setSourceRetryError('PDF access could not be refreshed. Try again.');
        return;
      }
      setActiveUrl(refreshedUrl);
      setSourceFailure(null);
      setDocumentAttempt(attempt => attempt + 1);
    } catch {
      if (!isPdfSourceRequestCurrent(
        { generation: requestGeneration, sourceIdentity: requestedIdentity },
        sourceRequestCurrentRef.current,
      )) return;
      setSourceRetryError('PDF access could not be refreshed. Try again.');
    } finally {
      if (sourceRequestGenerationRef.current === requestGeneration) setIsSourceRetryPending(false);
    }
  }

  function retryPage(page: number) {
    setPageFailures(current => ({ ...current, [page]: false }));
    setPageAttempts(current => ({ ...current, [page]: (current[page] ?? 0) + 1 }));
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
    if (!thumbnailsOpen) return;
    const container = thumbnailStripRef.current;
    const element = thumbnailElementsRef.current.get(pageNumber);
    if (!container || !element) return;
    const frame = window.requestAnimationFrame(() => {
      container.scrollTo({
        left: Math.max(0, element.offsetLeft - (container.clientWidth - element.offsetWidth) / 2),
      });
    });
    return () => window.cancelAnimationFrame(frame);
  }, [pageNumber, thumbnailsOpen]);

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
    setFitPage(false);
    setScale(current => Math.min(3, Math.max(0.5, current + delta)));
    preserveCurrentPageAfterLayout();
  }

  function fitPageWidth() {
    setFitWidth(true);
    setFitPage(false);
    preserveCurrentPageAfterLayout();
  }

  function fitWholePage() {
    setFitWidth(false);
    setFitPage(true);
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
    if (fitPage) {
      const sourceSize = pageSizes[page];
      const rotated = rotation % 180 !== 0;
      const height = rotated ? (sourceSize?.width ?? 612) : (sourceSize?.height ?? 792);
      return height * pdfFitPageScale({ sourceSize, rotation, viewportWidth: pageWidth, viewportHeight: pageViewportHeight });
    }
    return pdfPageHeight({ sourceSize: pageSizes[page], rotation, fitWidth, pageWidth, scale });
  }

  function pageScale(page: number) {
    return fitPage
      ? pdfFitPageScale({ sourceSize: pageSizes[page], rotation, viewportWidth: pageWidth, viewportHeight: pageViewportHeight })
      : scale;
  }

  function changeSearchQuery(value: string) {
    searchGenerationRef.current += 1;
    setSearchQuery(value);
    setActiveSearchQuery('');
    setSearchedPages(0);
    setSearchResults([]);
    setActiveSearchResult(-1);
    setIsSearchPending(false);
    setSearchError(null);
  }

  function cancelSearch() {
    searchGenerationRef.current += 1;
    setIsSearchPending(false);
  }

  async function searchNextBatch() {
    const document = pdfDocumentRef.current;
    const query = normalizePdfSearchQuery(searchQuery);
    if (!document || !numPages || !query) return;
    const batch = nextPdfSearchBatch(searchedPages, numPages);
    if (batch.complete) return;

    const generation = searchGenerationRef.current + 1;
    searchGenerationRef.current = generation;
    setActiveSearchQuery(query);
    setIsSearchPending(true);
    setSearchError(null);
    const batchMatches: number[] = [];
    let lastScannedPage = batch.start - 1;

    try {
      for (let page = batch.start; page <= batch.end; page += 1) {
        const pageProxy = await document.getPage(page);
        const content = await pageProxy.getTextContent();
        if (searchGenerationRef.current !== generation || pdfDocumentRef.current !== document) return;
        const text = content.items.map((item) => 'str' in item ? item.str : '').join(' ');
        if (text.toLowerCase().includes(query.toLowerCase())) batchMatches.push(page);
        lastScannedPage = page;
      }

      const mergedResults = Array.from(new Set([...searchResults, ...batchMatches]));
      setSearchResults(mergedResults);
      setSearchedPages(batch.end);
      if (activeSearchResult < 0 && mergedResults.length > 0) {
        setActiveSearchResult(0);
        requestPage(mergedResults[0]);
      }
    } catch {
      if (searchGenerationRef.current !== generation || pdfDocumentRef.current !== document) return;
      const mergedResults = Array.from(new Set([...searchResults, ...batchMatches]));
      setSearchResults(mergedResults);
      setSearchedPages(lastScannedPage);
      setSearchError(`Search stopped at page ${lastScannedPage + 1}. Coverage is complete through page ${lastScannedPage}.`);
    } finally {
      if (searchGenerationRef.current === generation) setIsSearchPending(false);
    }
  }

  function navigateSearchResult(direction: -1 | 1) {
    const nextIndex = Math.min(searchResults.length - 1, Math.max(0, activeSearchResult + direction));
    setActiveSearchResult(nextIndex);
    const matchPage = searchResults[nextIndex];
    if (matchPage) requestPage(matchPage);
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
    const browserSelection = window.getSelection();
    const text = browserSelection?.toString().trim();
    const nodeElement = (node: Node | null | undefined) => node instanceof HTMLElement ? node : node?.parentElement;
    const anchorPage = nodeElement(browserSelection?.anchorNode)?.closest<HTMLElement>('[data-pdf-page]');
    const focusPage = nodeElement(browserSelection?.focusNode)?.closest<HTMLElement>('[data-pdf-page]');
    const selectedPageNumber = Number(anchorPage?.dataset.pdfPage);
    const isSingleViewerPage = Boolean(
      text && quoteSource && onCreateQuotation && anchorPage && focusPage
      && anchorPage === focusPage && scrollContainerRef.current?.contains(anchorPage)
      && Number.isSafeInteger(selectedPageNumber) && selectedPageNumber > 0,
    );
    if (isSingleViewerPage && text) {
      // Calculate position for the floating button (relative to viewport)
      setSelection({
        text,
        x: e.clientX,
        y: e.clientY,
        pageNumber: selectedPageNumber,
      });
    } else {
      setSelection(null);
    }
  };

  const handleAddNoteClick = () => {
    if (selection && quoteSource && onCreateQuotation) {
      const quotation = createPdfQuotationSelection(quoteSource, selection.text, selection.pageNumber, numPages ?? 0);
      if (!quotation) return;
      onCreateQuotation(quotation);
      setSelection(null);
      window.getSelection()?.removeAllRanges();
    }
  };

  const thumbnailPages = numPages ? pdfThumbnailPages(pageNumber, numPages) : [];
  const sourceFailureCopy = sourceFailure ? pdfSourceFailureCopy(sourceFailure) : null;

  return (
    <div className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-[var(--surface)]">
      {/* Toolbar */}
      <div className="z-10 flex min-h-14 w-full shrink-0 flex-wrap items-center justify-center gap-1 border-b border-[var(--border)] bg-[var(--surface)] p-2 sm:gap-2">
        <Button variant="ghost" size="icon" className="min-h-11 min-w-11" aria-label="Previous page" title="Previous page" onClick={previousPage} disabled={Boolean(sourceFailure) || pageNumber <= 1}>
          <ChevronLeft size={16} />
        </Button>
        <label className="flex min-h-11 items-center gap-1 text-sm font-medium text-[var(--text-primary)]">
          <span className="sr-only">Current PDF page</span>
          <input
            type="number"
            min={1}
            max={numPages}
            value={pageNumber}
            disabled={Boolean(sourceFailure)}
            onChange={event => requestPage(Number(event.target.value) || 1)}
            className="h-9 w-14 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-2 text-center text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
          />
          <span className="whitespace-nowrap text-[var(--text-muted)]">of {numPages || '--'}</span>
        </label>
        <Button variant="ghost" size="icon" className="min-h-11 min-w-11" aria-label="Next page" title="Next page" onClick={nextPage} disabled={Boolean(sourceFailure) || pageNumber >= (numPages || 1)}>
          <ChevronRight size={16} />
        </Button>

        <div className="mx-1 hidden h-6 w-px bg-[var(--border)] sm:block" />

        <Button variant="ghost" size="icon" className="min-h-11 min-w-11" aria-label="Zoom out" title="Zoom out" onClick={() => zoomBy(-0.2)} disabled={Boolean(sourceFailure)}>
          <ZoomOut size={16} />
        </Button>
        <span className="w-12 text-center text-sm font-medium text-[var(--text-primary)]">
          {fitWidth ? 'Width' : fitPage ? 'Page' : `${Math.round(scale * 100)}%`}
        </span>
        <Button variant="ghost" size="icon" className="min-h-11 min-w-11" aria-label="Zoom in" title="Zoom in" onClick={() => zoomBy(0.2)} disabled={Boolean(sourceFailure)}>
          <ZoomIn size={16} />
        </Button>
        <Button type="button" variant="outline" className="min-h-11" onClick={fitPageWidth} aria-pressed={fitWidth} disabled={Boolean(sourceFailure)}>
          <PanelTop size={16} aria-hidden="true" />
          Fit width
        </Button>
        <Button type="button" variant="outline" className="min-h-11" onClick={fitWholePage} aria-pressed={fitPage} disabled={Boolean(sourceFailure)}>
          <PanelTop size={16} aria-hidden="true" />
          Fit page
        </Button>
        <Button
          type="button"
          variant="outline"
          className="min-h-11"
          onClick={rotateClockwise}
          disabled={Boolean(sourceFailure)}
          aria-label={`Rotate PDF clockwise. Current rotation ${rotation} degrees`}
          title={`Current rotation: ${rotation}°`}
        >
          <RotateCw size={16} aria-hidden="true" />
          Rotate
        </Button>
        <Button
          type="button"
          variant="outline"
          className="min-h-11"
          onClick={() => setThumbnailsOpen(open => !open)}
          disabled={Boolean(sourceFailure)}
          aria-expanded={thumbnailsOpen}
          aria-controls={thumbnailStripId}
        >
          <PanelLeft size={16} aria-hidden="true" />
          {thumbnailsOpen ? 'Hide thumbnails' : 'Show thumbnails'}
        </Button>
      </div>

      <form
        className="flex min-h-14 w-full shrink-0 flex-wrap items-center gap-2 border-b border-[var(--border)] bg-[var(--surface)] p-2"
        onSubmit={(event) => {
          event.preventDefault();
          void searchNextBatch();
        }}
      >
        <label htmlFor={searchInputId} className="sr-only">Search selectable PDF text</label>
        <div className="relative min-w-48 flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
          <Input
            id={searchInputId}
            value={searchQuery}
            onChange={(event) => changeSearchQuery(event.target.value)}
            placeholder="Search selectable PDF text"
            className="h-11 pl-9 pr-10"
          />
          {searchQuery && !isSearchPending && (
            <button
              type="button"
              onClick={() => changeSearchQuery('')}
              className="absolute right-0 top-0 flex size-11 items-center justify-center text-[var(--text-muted)] hover:text-[var(--text-primary)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]"
              aria-label="Clear PDF search"
              title="Clear PDF search"
            >
              <X className="size-4" aria-hidden="true" />
            </button>
          )}
        </div>
        {isSearchPending ? (
          <Button type="button" variant="outline" className="min-h-11" onClick={cancelSearch}>Cancel search</Button>
        ) : (
          <Button
            type="submit"
            variant="outline"
            className="min-h-11"
            disabled={!normalizePdfSearchQuery(searchQuery) || !numPages || searchedPages >= numPages}
          >
            {searchedPages >= (numPages ?? 0) && numPages
              ? 'Search complete'
              : searchedPages > 0
                ? `Search next ${Math.min(PDF_SEARCH_BATCH_SIZE, Math.max(0, (numPages ?? 0) - searchedPages))} pages`
                : 'Search PDF'}
          </Button>
        )}
        {activeSearchQuery && (
          <div className="flex min-h-11 flex-wrap items-center gap-1 text-xs text-[var(--text-muted)]" aria-live="polite">
            <span className="whitespace-nowrap">Searched {searchedPages} of {numPages ?? 0} pages · {searchResults.length} matching pages</span>
            {searchResults.length > 0 && (
              <>
                <Button type="button" variant="ghost" size="icon" className="min-h-11 min-w-11" onClick={() => navigateSearchResult(-1)} disabled={activeSearchResult <= 0} aria-label="Previous matching page" title="Previous matching page">
                  <ChevronLeft className="size-4" aria-hidden="true" />
                </Button>
                <span className="min-w-12 text-center">{activeSearchResult + 1} of {searchResults.length}</span>
                <Button type="button" variant="ghost" size="icon" className="min-h-11 min-w-11" onClick={() => navigateSearchResult(1)} disabled={activeSearchResult >= searchResults.length - 1} aria-label="Next matching page" title="Next matching page">
                  <ChevronRight className="size-4" aria-hidden="true" />
                </Button>
              </>
            )}
          </div>
        )}
        {searchError && <p role="alert" className="w-full text-xs text-[var(--danger)]">{searchError}</p>}
      </form>

      {sourceFailureCopy ? (
        <div role="alert" className="flex min-h-0 flex-1 flex-col items-center justify-center gap-4 bg-[var(--bg-overlay)] p-6 text-center">
          <span className="flex size-11 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--danger-muted)] text-[var(--danger)]">
            <FileText className="size-5" aria-hidden="true" />
          </span>
          <div className="max-w-md space-y-1">
            <h2 className="text-section-heading text-[var(--text-primary)]">{sourceFailureCopy.title}</h2>
            <p className="text-body text-[var(--text-secondary)]">{sourceFailureCopy.detail}</p>
          </div>
          {sourceFailureCopy.retryable && (
            <Button type="button" variant="outline" className="min-h-11" onClick={() => void retrySource()} loading={isSourceRetryPending}>
              <RefreshCw className="size-4" aria-hidden="true" />
              {sourceFailureCopy.retryLabel}
            </Button>
          )}
          {sourceRetryError && <p role="alert" className="text-sm text-[var(--danger)]">{sourceRetryError}</p>}
        </div>
      ) : (
      <Document
        key={`${activeUrl}:${documentAttempt}`}
        file={activeUrl!}
        onLoadSuccess={onDocumentLoadSuccess}
        onLoadError={onDocumentLoadError}
        onSourceError={onDocumentSourceError}
        onPassword={() => presentSourceFailure('encrypted')}
        className="flex min-h-0 w-full flex-1 flex-col overflow-hidden"
        loading={<div role="status" className="flex min-h-0 flex-1 animate-pulse items-center justify-center p-10 font-medium text-[var(--text-muted)] motion-reduce:animate-none">Loading PDF source…</div>}
        error={<div role="alert" className="p-10 font-medium text-[var(--danger)]">PDF could not be opened.</div>}
      >
        {thumbnailsOpen && numPages && (
          <nav
            id={thumbnailStripId}
            aria-label="PDF page thumbnails"
            className="shrink-0 border-b border-[var(--border)] bg-[var(--surface)] p-2"
          >
            <div
              ref={thumbnailStripRef}
              className="custom-scrollbar flex max-w-full gap-2 overflow-x-auto overscroll-x-contain pb-1"
            >
              {thumbnailPages[0] > 1 && (
                <Button
                  type="button"
                  variant="ghost"
                  className="min-h-11 shrink-0"
                  onClick={() => requestPage(thumbnailPages[0] - 1)}
                >
                  Earlier pages
                </Button>
              )}
              {thumbnailPages.map((page) => {
                const selected = page === pageNumber;
                return (
                  <button
                    key={page}
                    ref={(element) => {
                      if (element) thumbnailElementsRef.current.set(page, element);
                      else thumbnailElementsRef.current.delete(page);
                    }}
                    type="button"
                    onClick={() => requestPage(page)}
                    aria-current={selected ? 'page' : undefined}
                    aria-label={`Go to PDF page ${page}`}
                    className="flex min-h-11 w-20 shrink-0 flex-col items-center gap-1 rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--surface)] p-1 text-xs text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] aria-[current=page]:border-[var(--accent)] aria-[current=page]:bg-[var(--accent-muted)] aria-[current=page]:text-[var(--text-primary)]"
                  >
                    <span className="flex h-[92px] w-[72px] items-center justify-center overflow-hidden bg-[var(--bg-overlay)] shadow-[var(--shadow-xs)]" aria-hidden="true">
                      <Page
                        pageNumber={page}
                        width={72}
                        rotate={rotation}
                        renderTextLayer={false}
                        renderAnnotationLayer={false}
                      />
                    </span>
                    <span>Page {page}</span>
                  </button>
                );
              })}
              {thumbnailPages.at(-1)! < numPages && (
                <Button
                  type="button"
                  variant="ghost"
                  className="min-h-11 shrink-0"
                  onClick={() => requestPage(thumbnailPages.at(-1)! + 1)}
                >
                  Later pages
                </Button>
              )}
            </div>
          </nav>
        )}

        {/* PDF Container */}
        <div
          ref={scrollContainerRef}
          tabIndex={0}
          role="region"
          aria-label="PDF page viewer"
          aria-keyshortcuts="ArrowLeft ArrowRight PageUp PageDown Home End"
          className="custom-scrollbar relative flex min-h-0 w-full flex-1 flex-col items-center gap-4 overflow-auto bg-[var(--bg-overlay)] p-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)] sm:p-4"
          onMouseUp={handleMouseUp}
          onKeyDown={handleViewerKeyDown}
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
                  pageFailures[page] ? (
                    <div role="alert" className="flex min-h-44 w-full max-w-md flex-col items-center justify-center gap-3 border border-[var(--border)] bg-[var(--surface)] p-4 text-center">
                      <p className="text-sm font-medium text-[var(--text-primary)]">Page {page} could not be rendered.</p>
                      <Button type="button" variant="outline" className="min-h-11" onClick={() => retryPage(page)}>Retry page</Button>
                    </div>
                  ) : (
                    <Page
                      key={`${page}:${pageAttempts[page] ?? 0}`}
                      pageNumber={page}
                      width={fitWidth ? pageWidth : undefined}
                      scale={fitWidth ? undefined : pageScale(page)}
                      rotate={rotation}
                      onLoadSuccess={(proxy) => recordPageSize(page, proxy)}
                      onLoadError={() => setPageFailures(current => ({ ...current, [page]: true }))}
                      onRenderError={() => setPageFailures(current => ({ ...current, [page]: true }))}
                      customTextRenderer={searchResults.includes(page)
                        ? ({ str }) => highlightPdfText(str, activeSearchQuery)
                        : undefined}
                      className="shadow-[var(--shadow-lg)]"
                      renderTextLayer={true}
                      renderAnnotationLayer={true}
                    />
                  )
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

          {/* Floating Add Note Button */}
          {selection && (
            <div
              style={{ position: 'fixed', top: selection.y - 45, left: selection.x - 20, zIndex: 50 }}
              className="animate-fade-in"
            >
              <Button
                size="sm"
                onClick={handleAddNoteClick}
                className="min-h-11 shadow-[var(--shadow-md)]"
              >
                <MessageSquarePlus size={14} /> Add Note
              </Button>
            </div>
          )}
        </div>
      </Document>
      )}
    </div>
  );
}
