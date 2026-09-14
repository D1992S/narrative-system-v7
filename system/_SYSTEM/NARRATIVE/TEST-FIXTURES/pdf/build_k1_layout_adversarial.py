#!/usr/bin/env python3
"""Build the one deterministic real-PDF layout fixture used by K1 tests."""

from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas


OUTPUT = Path(__file__).with_name("k1-layout-adversarial.pdf")
WIDTH, HEIGHT = A4


def body_line(pdf: canvas.Canvas, y: float, text: str, x: float = 62) -> None:
    pdf.setFont("Helvetica", 11)
    pdf.drawString(x, y, text)


def main() -> None:
    pdf = canvas.Canvas(
        str(OUTPUT),
        pagesize=A4,
        pageCompression=0,
        invariant=1,
        title="K1 layout adversarial fixture",
        author="System-v7.0 tests",
    )

    # P0001: exact adjacent lines and a deliberately non-adjacent pair.
    pdf.setFont("Helvetica-Bold", 14)
    pdf.drawString(62, HEIGHT - 62, "PAGE 1 - LINE LOCALITY")
    lines = [
        "ADJACENT ALPHA: The first claim starts here.",
        "ADJACENT BETA: The second claim follows immediately.",
        "SEPARATOR: This line must prevent a fabricated continuous quotation.",
        "DISTANT OMEGA: The later claim is not adjacent to alpha.",
    ]
    for index, text in enumerate(lines):
        body_line(pdf, HEIGHT - 105 - index * 22, text)
    pdf.showPage()

    # P0002: genuine simultaneous left and right text columns.
    pdf.setFont("Helvetica-Bold", 14)
    pdf.drawString(62, HEIGHT - 62, "PAGE 2 - TWO COLUMNS")
    for index in range(7):
        y = HEIGHT - 110 - index * 26
        body_line(pdf, y, f"LEFT {index + 1}: independent left-column evidence.", 62)
        body_line(pdf, y, f"RIGHT {index + 1}: independent right-column evidence.", 330)
    pdf.showPage()

    # P0003: normal body mixed with a small bottom footnote.
    pdf.setFont("Helvetica-Bold", 14)
    pdf.drawString(62, HEIGHT - 62, "PAGE 3 - FOOTNOTE MIX")
    for index in range(8):
        body_line(pdf, HEIGHT - 108 - index * 24, f"BODY {index + 1}: Main narrative text remains in the upper page region.")
    pdf.setLineWidth(0.6)
    pdf.line(62, 104, WIDTH - 62, 104)
    pdf.setFont("Helvetica", 7)
    pdf.drawString(62, 88, "1 SMALL FOOTNOTE: This note must not be silently merged into the body.")
    pdf.showPage()

    # P0004: body, a vector figure, and a small caption immediately below it.
    pdf.setFont("Helvetica-Bold", 14)
    pdf.drawString(62, HEIGHT - 62, "PAGE 4 - CAPTION MIX")
    for index in range(5):
        body_line(pdf, HEIGHT - 108 - index * 24, f"BODY {index + 1}: Main text precedes a separate figure and caption.")
    figure_x, figure_y, figure_w, figure_h = 150, 250, 290, 170
    pdf.setLineWidth(1)
    pdf.rect(figure_x, figure_y, figure_w, figure_h, stroke=1, fill=0)
    pdf.line(figure_x, figure_y, figure_x + figure_w, figure_y + figure_h)
    pdf.line(figure_x, figure_y + figure_h, figure_x + figure_w, figure_y)
    pdf.setFont("Helvetica", 7)
    pdf.drawCentredString(WIDTH / 2, figure_y - 16, "FIGURE 1: Small caption belongs to the drawing, not to body prose.")
    pdf.showPage()

    # P0005: a scanned/textless page. Tests attach OCR text in the sidecar;
    # the backing PDF deliberately exposes no native text geometry.
    pdf.setLineWidth(1)
    pdf.rect(90, 150, WIDTH - 180, HEIGHT - 300, stroke=1, fill=0)
    for offset in range(0, 360, 36):
        pdf.line(110, 190 + offset, WIDTH - 110, 190 + offset)
    pdf.showPage()

    pdf.save()
    print(OUTPUT)


if __name__ == "__main__":
    main()
