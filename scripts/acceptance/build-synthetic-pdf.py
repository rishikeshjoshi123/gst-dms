from pathlib import Path

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas


OUTPUT = Path(__file__).resolve().parents[2] / "tests" / "acceptance" / "fixtures" / "synthetic-multi-page.pdf"
CONFLICT_OUTPUT = OUTPUT.with_name("synthetic-extraction-conflict.pdf")
PLACEMENT_OUTPUT = OUTPUT.with_name("synthetic-placement-conflict.pdf")
PLACEMENT_SECOND_OUTPUT = OUTPUT.with_name("synthetic-placement-conflict-second.pdf")
PAGE_COPY = (
    ("CaseChain acceptance source", "Order in Original", "Reference OIO/ASTER/2026/17"),
    ("Chronology evidence", "Demand confirmed", "Synthetic amount INR 125,000"),
    ("Exact source location", "Requested page 3", "Distinct marker ACCEPTANCE-PAGE-THREE"),
    ("Closing fixture page", "Recovery boundary", "No real client or provider data"),
)
CONFLICT_PAGE_COPY = (
    ("Competing document labels", "Document type OIO", "Order in Original label printed above"),
    ("Competing document labels", "Document type SCN", "Show Cause Notice label printed above"),
    ("Source interpretation", "Human decision required", "The two printed type labels conflict."),
    ("Closing fixture page", "Synthetic source only", "No real client or provider data"),
)
PLACEMENT_PAGE_COPY = (
    ("Placed document identity", "GST Tribunal order", "References GST/555/2026 in this proceeding."),
)
PLACEMENT_SECOND_PAGE_COPY = (
    ("Placed document identity", "Second source, same typed key", "References GST/555/2026 in this proceeding."),
)


def build(output: Path = OUTPUT, page_copy=PAGE_COPY) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    pdf = canvas.Canvas(str(output), pagesize=A4, invariant=1, pageCompression=1)
    pdf.setTitle("CaseChain synthetic multi-page acceptance source")
    pdf.setAuthor("CaseChain local acceptance")
    width, height = A4

    for page_number, lines in enumerate(page_copy, start=1):
        pdf.setFillColor(HexColor("#18212A"))
        pdf.rect(0, height - 86, width, 86, fill=1, stroke=0)
        pdf.setFillColor(HexColor("#FFFFFF"))
        pdf.setFont("Helvetica-Bold", 18)
        pdf.drawString(48, height - 54, lines[0])

        pdf.setFillColor(HexColor("#18212A"))
        pdf.setFont("Helvetica-Bold", 26)
        pdf.drawString(48, height - 150, f"Synthetic Acceptance Page {page_number}")
        pdf.setFont("Helvetica-Bold", 15)
        pdf.drawString(48, height - 202, lines[1])
        pdf.setFont("Helvetica", 12)
        pdf.drawString(48, height - 232, lines[2])
        pdf.drawString(48, height - 278, "This generated document contains no client information.")
        pdf.drawString(48, height - 298, "It is safe for disposable local browser and Storage checks.")

        pdf.setStrokeColor(HexColor("#A8B0B7"))
        pdf.line(48, 58, width - 48, 58)
        pdf.setFont("Helvetica", 9)
        pdf.drawString(48, 38, "Synthetic local fixture")
        pdf.drawRightString(width - 48, 38, f"Page {page_number} of {len(page_copy)}")
        pdf.showPage()

    pdf.save()


if __name__ == "__main__":
    build(CONFLICT_OUTPUT, CONFLICT_PAGE_COPY)
    build(PLACEMENT_OUTPUT, PLACEMENT_PAGE_COPY)
    build(PLACEMENT_SECOND_OUTPUT, PLACEMENT_SECOND_PAGE_COPY)
