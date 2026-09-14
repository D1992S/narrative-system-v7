#!/usr/bin/env python3
"""Create the deterministic, synthetic K1-Lite PDF test fixture."""

from __future__ import annotations

import argparse
import io
from pathlib import Path

import fitz
from PIL import Image, ImageDraw, ImageFont


PAGE = fitz.paper_rect("a4")
ARIAL = Path(r"C:\Windows\Fonts\arial.ttf")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def add_font(page: fitz.Page) -> str:
    if ARIAL.is_file():
        page.insert_font(fontname="FixtureArial", fontfile=str(ARIAL))
        return "FixtureArial"
    return "helv"


def add_text_page(doc: fitz.Document, lines: list[str], *, rotate_text: bool = False) -> None:
    page = doc.new_page(width=PAGE.width, height=PAGE.height)
    font = add_font(page)
    if rotate_text:
        point = fitz.Point(500, 760)
        for line in lines:
            page.insert_text(point, line, fontname=font, fontsize=14, rotate=90)
            point.x -= 24
        return
    y = 72
    for line in lines:
        if line:
            page.insert_text((56, y), line, fontname=font, fontsize=12)
        y += 22


def add_scan_page(doc: fitz.Document, lines: list[str]) -> None:
    image = Image.new("RGB", (1654, 2339), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(ARIAL), 46) if ARIAL.is_file() else ImageFont.load_default()
    y = 170
    for line in lines:
        draw.text((130, y), line, fill="black", font=font)
        y += 86
    payload = io.BytesIO()
    image.save(payload, format="PNG")
    page = doc.new_page(width=PAGE.width, height=PAGE.height)
    page.insert_image(page.rect, stream=payload.getvalue())


def add_table_page(doc: fitz.Document) -> None:
    page = doc.new_page(width=PAGE.width, height=PAGE.height)
    font = add_font(page)
    headers = ["Rok", "Zdarzenie", "Ocena"]
    rows = [
        ["1908", "Pierwszy zapis", "wstępna"],
        ["1954", "Drugie świadectwo", "sporna"],
        ["1999", "Publikacja katalogu", "potwierdzona"],
    ]
    x = [56, 150, 390, 535]
    y0, row_h = 95, 42
    for row_index in range(len(rows) + 2):
        y = y0 + row_index * row_h
        page.draw_line((x[0], y), (x[-1], y), color=(0, 0, 0), width=0.8)
    for column_x in x:
        page.draw_line((column_x, y0), (column_x, y0 + (len(rows) + 1) * row_h), color=(0, 0, 0), width=0.8)
    for column, value in enumerate(headers):
        page.insert_text((x[column] + 7, y0 + 27), value, fontname=font, fontsize=11)
    for row_index, row in enumerate(rows, start=1):
        for column, value in enumerate(row):
            page.insert_text((x[column] + 7, y0 + row_index * row_h + 27), value, fontname=font, fontsize=10)


def add_columns_page(doc: fitz.Document) -> None:
    page = doc.new_page(width=PAGE.width, height=PAGE.height)
    font = add_font(page)
    left = [
        "LEWA KOLUMNA",
        "Pierwszy niezależny wątek.",
        "Drugi akapit zachowuje kolejność.",
        "Trzeci wiersz kończy kolumnę.",
    ]
    right = [
        "PRAWA KOLUMNA",
        "Osobny materiał porównawczy.",
        "Dane nie mogą mieszać się z lewą.",
        "Ostatni wiersz prawej kolumny.",
    ]
    for start_x, values in ((56, left), (320, right)):
        y = 90
        for value in values:
            page.insert_text((start_x, y), value, fontname=font, fontsize=11)
            y += 30


def build(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise FileExistsError(f"Refusing to overwrite fixture: {output}")

    doc = fitz.open()
    add_text_page(
        doc,
        [
            "STRONA 1 — TEKST NATYWNY PO POLSKU",
            "Zażółć gęślą jaźń. Źródło zachowuje polskie znaki.",
            "Wyjątkowy cytat tylko na stronie pierwszej.",
            "",
            "Wewnętrzna pusta linia musi pozostać w bloku strony.",
        ],
    )
    add_text_page(
        doc,
        [
            "PAGE 2 — NATIVE ENGLISH TEXT",
            "This page contains a short English source passage.",
            "The same sentence appears on two physical pages.",
            "The locator must remain page-local.",
        ],
    )
    add_scan_page(
        doc,
        [
            "STRONA 3 — CZYSTY SKAN",
            "OCR powinien odczytać tylko jawnie wskazaną stronę.",
            "Skanowany dowód numer 31415.",
        ],
    )
    doc.new_page(width=PAGE.width, height=PAGE.height)
    add_table_page(doc)
    add_columns_page(doc)
    add_text_page(
        doc,
        [
            "STRONA 7 — TEKST OBRÓCONY",
            "Orientacja jest częścią testu wizualnego.",
            "Nie wolno zgubić fizycznego numeru strony.",
        ],
        rotate_text=True,
    )
    add_text_page(
        doc,
        [
            "STRONA 8 — POLSKIE ZNAKI I CYFRY",
            "Ćma, źrebak, łódź, gęś, żółw; liczby: 0 1 2 3 4 5 6 7 8 9.",
            "The same sentence appears on two physical pages.",
            "Sygnatura: PL-2026/08/30-A7.",
        ],
    )
    add_scan_page(
        doc,
        [
            "STRONA 9 — DRUGI SKAN",
            "Druga strona OCR pozwala sprawdzić selektywność.",
            "Kod kontrolny OCR dziewięć osiem siedem.",
        ],
    )
    add_text_page(
        doc,
        [
            "STRONA 10 — CYTAT BLISKO GRANICY",
            "Treść końcowa leży tuż przy technicznej granicy strony.",
            "Cytat nie może pochodzić z frontmattera ani znacznika.",
        ],
    )
    doc.set_metadata({"title": "K1-Lite synthetic fixture", "author": "System-v7 test"})
    doc.save(output, garbage=4, deflate=True, clean=True)
    doc.close()


if __name__ == "__main__":
    build(parse_args().output.resolve())

