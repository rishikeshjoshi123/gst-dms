from pathlib import Path

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas


OUTPUT = Path(__file__).resolve().parents[2] / "tests" / "acceptance" / "fixtures" / "synthetic-multi-page.pdf"
PAGE_COPY = (
    ("CaseChain acceptance source", "Order in Original", "Reference OIO/ASTER/2026/17"),
    ("Chronology evidence", "Demand confirmed", "Synthetic amount INR 125,000"),
    ("Exact source location", "Requested page 3", "Distinct marker ACCEPTANCE-PAGE-THREE"),
    ("Closing fixture page", "Recovery boundary", "No real client or provider data"),
)


def build() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    pdf = canvas.Canvas(str(OUTPUT), pagesize=A4, invariant=1, pageCompression=1)
    pdf.setTitle("CaseChain synthetic multi-page acceptance source")
    pdf.setAuthor("CaseChain local acceptance")
    width, height = A4

    for page_number, lines in enumerate(PAGE_COPY, start=1):
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
        pdf.drawRightString(width - 48, 38, f"Page {page_number} of {len(PAGE_COPY)}")
        pdf.showPage()

    pdf.save()


if __name__ == "__main__":
    build()
