'use client'

import { useState, useEffect } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import 'react-pdf/dist/Page/AnnotationLayer.css';
import 'react-pdf/dist/Page/TextLayer.css';
import { ChevronLeft, ChevronRight, ZoomIn, ZoomOut, MessageSquarePlus } from 'lucide-react';
import { Button } from './button';

// Configure the worker for pdf.js
pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  'pdfjs-dist/build/pdf.worker.min.mjs',
  import.meta.url,
).toString();

export function PdfViewer({ url }: { url: string }) {
  const [numPages, setNumPages] = useState<number>();
  const [pageNumber, setPageNumber] = useState<number>(1);
  const [scale, setScale] = useState<number>(1.0);

  const [selection, setSelection] = useState<{ text: string, x: number, y: number } | null>(null);

  // Listen for jump events from the notes panel
  useEffect(() => {
    const handleJump = (e: CustomEvent) => {
      if (e.detail && typeof e.detail.pageNumber === 'number') {
        setPageNumber(e.detail.pageNumber);
      }
    };
    window.addEventListener('JUMP_TO_PDF_PAGE', handleJump as EventListener);
    return () => window.removeEventListener('JUMP_TO_PDF_PAGE', handleJump as EventListener);
  }, []);

  function onDocumentLoadSuccess({ numPages }: { numPages: number }): void {
    setNumPages(numPages);
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
    <div className="flex flex-col items-center w-full h-full bg-[var(--bg-surface)]">
      {/* Toolbar */}
      <div className="flex items-center gap-2 p-2 mb-4 bg-white border border-[var(--border)] shadow-sm rounded-lg sticky top-0 z-10 w-fit">
        <Button variant="ghost" size="icon" onClick={() => setPageNumber(p => Math.max(1, p - 1))} disabled={pageNumber <= 1}>
          <ChevronLeft size={16} />
        </Button>
        <span className="text-sm font-medium text-[var(--text-primary)] min-w-[100px] text-center">
          Page {pageNumber} of {numPages || '--'}
        </span>
        <Button variant="ghost" size="icon" onClick={() => setPageNumber(p => Math.min(numPages || 1, p + 1))} disabled={pageNumber >= (numPages || 1)}>
          <ChevronRight size={16} />
        </Button>

        <div className="w-px h-6 bg-[var(--border)] mx-2" />

        <Button variant="ghost" size="icon" onClick={() => setScale(s => Math.max(0.5, s - 0.2))}>
          <ZoomOut size={16} />
        </Button>
        <span className="text-sm font-medium w-12 text-center text-[var(--text-primary)]">
          {Math.round(scale * 100)}%
        </span>
        <Button variant="ghost" size="icon" onClick={() => setScale(s => Math.min(3, s + 0.2))}>
          <ZoomIn size={16} />
        </Button>
      </div>

      {/* PDF Container */}
      <div 
        className="flex-1 overflow-auto w-full flex justify-center rounded-lg bg-[var(--border)] p-4 shadow-inner min-h-[600px] relative"
        onMouseUp={handleMouseUp}
      >
        <Document 
          file={url} 
          onLoadSuccess={onDocumentLoadSuccess} 
          loading={<div className="p-10 font-medium text-[var(--text-muted)] animate-pulse">Loading PDF Document...</div>}
          error={<div className="p-10 font-medium text-[var(--danger)]">Failed to load PDF. Please try again later.</div>}
        >
          <Page 
            pageNumber={pageNumber} 
            scale={scale} 
            className="shadow-xl" 
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
