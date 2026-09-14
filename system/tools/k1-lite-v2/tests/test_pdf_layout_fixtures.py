#!/usr/bin/env python3
"""Real-PDF regression for page locality and risky layout detection."""

from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
SYSTEM_ROOT = HERE.parents[2]
FIXTURE = SYSTEM_ROOT / "_SYSTEM" / "NARRATIVE" / "TEST-FIXTURES" / "pdf" / "k1-layout-adversarial.pdf"
sys.path.insert(0, str(HERE.parent))

from k1_lite_v2_core import (  # noqa: E402
    K1LiteV2Error,
    find_quote,
    import_worker_result,
    initialize_run,
    inspect_pdf_layout,
    quote_pdf_layout_violations,
    read_jsonl,
    read_source,
    sha256_bytes,
    sha256_file,
)


class RealPdfLayoutFixtureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="k1-real-pdf-")
        self.root = Path(self.temporary.name).resolve()
        source_dir = self.root / "PROJECT" / "sources"
        source_dir.mkdir(parents=True)
        self.pdf = source_dir / "k1-layout-adversarial.pdf"
        shutil.copy2(FIXTURE, self.pdf)

        import fitz

        blocks: list[str] = []
        with fitz.open(self.pdf) as document:
            self.assertEqual(document.page_count, 5)
            for number, page in enumerate(document, start=1):
                extracted = page.get_text("text").replace("\r\n", "\n").replace("\r", "\n").strip("\n")
                body = extracted if number != 5 else (
                    "OCR BODY ONE: Scanned paragraph reconstructed by OCR.\n"
                    "OCR BODY TWO: A second reconstructed body line.\n"
                    "OCR NOTE: A visually separate note has no native geometry."
                )
                page_hash = sha256_bytes((body + "\n" if body else "").encode("utf-8"))
                method = "NATIVE" if number != 5 else "OCR"
                flags = "NONE" if number != 5 else "LAYOUT_REVIEW_REQUIRED"
                blocks.append(
                    f"<!-- PDF_PAGE_BEGIN: P{number:04d}; METHOD: {method}; "
                    f"PAGE_TEXT_SHA256: {page_hash}; FLAGS: {flags} -->\n"
                    f"{body}\n<!-- PDF_PAGE_END: P{number:04d} -->\n"
                )
        self.source = source_dir / "k1-layout-adversarial--TEXT.md"
        self.source.write_text(
            "---\n"
            "PDF_TEXT_SCHEMA: K1_LITE_PDF_TEXT_V1\n"
            'ORIGINAL_PDF: "sources/k1-layout-adversarial.pdf"\n'
            f"ORIGINAL_PDF_SHA256: {sha256_file(self.pdf)}\n"
            "PHYSICAL_PAGES: 5\n"
            "OCR_LANGUAGES: none\n"
            "OCR_ENGINE: tesseract\n"
            "---\n\n"
            + "\n".join(blocks),
            encoding="utf-8",
            newline="\n",
        )
        self.run_dir = self.root / "_work" / "K1" / "k1-lite-v2" / "run-layout"
        self.run = initialize_run(
            isolation_root=self.root,
            source_path=self.source,
            expected_source_sha=sha256_file(self.source),
            pdf_path=self.pdf,
            expected_pdf_sha=sha256_file(self.pdf),
            run_dir=self.run_dir,
            k0_path=None,
            expected_k0_sha=None,
            target_min=1000,
            target_max=4000,
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_layout_risks_are_physically_detected(self) -> None:
        report = inspect_pdf_layout(
            isolation_root=self.root,
            run_dir=self.run_dir,
            output_path=self.run_dir / "qa" / "layout.json",
        )
        by_page = {item["page"]: set(item["flags"]) for item in report["risk_pages"]}
        self.assertIn("POSSIBLE_MULTI_COLUMN", by_page["P0002"])
        self.assertIn("POSSIBLE_FOOTNOTE_BODY_MIX", by_page["P0003"])
        self.assertIn("POSSIBLE_CAPTION_BODY_MIX", by_page["P0004"])
        self.assertEqual(self.run["visual_policy"], "REQUIRED")

    def test_quote_must_be_exact_and_contiguous_on_one_page(self) -> None:
        document = read_source(
            self.source,
            sha256_file(self.pdf),
            expected_pdf_path=self.pdf,
            isolation_root=self.root,
        )
        page = document.pages[0]
        adjacent = (
            "ADJACENT ALPHA: The first claim starts here.\n"
            "ADJACENT BETA: The second claim follows immediately."
        )
        match = find_quote(page, adjacent)
        self.assertEqual(match["locator"], "P0001/L2-L3")
        with self.assertRaisesRegex(K1LiteV2Error, "QUOTE_NOT_FOUND"):
            find_quote(
                page,
                "ADJACENT ALPHA: The first claim starts here.\n"
                "DISTANT OMEGA: The later claim is not adjacent to alpha.",
            )
        with self.assertRaisesRegex(K1LiteV2Error, "QUOTE_NOT_FOUND"):
            find_quote(page, "ADJACENT ALPHA: The first claim was changed here.")

    def test_worker_cannot_join_columns_footnotes_or_captions(self) -> None:
        document = read_source(
            self.source,
            sha256_file(self.pdf),
            expected_pdf_path=self.pdf,
            isolation_root=self.root,
        )
        chunks = read_jsonl(self.run_dir / "chunks.jsonl")
        for page_number, expected_code in (
            (2, "QUOTE_JOINS_PARALLEL_COLUMNS"),
            (3, "QUOTE_JOINS_BODY_AND_FOOTNOTE"),
            (4, "QUOTE_JOINS_BODY_AND_CAPTION"),
        ):
            page = document.pages[page_number - 1]
            violations = quote_pdf_layout_violations(self.pdf, page_number, page.body)
            self.assertIn(expected_code, violations)
            page_label = f"P{page_number:04d}"
            chunk = next(item for item in chunks if page_label in item["pages"])
            payload = {
                "schema": "K1_LITE_V2_WORKER_RESULT_V1",
                "run_id": self.run["run_id"],
                "chunk_id": chunk["chunk_id"],
                "chunk_sha256": chunk["chunk_sha256"],
                "continuation_no": 0,
                "status": "CANDIDATE",
                "more_strong_candidates": False,
                "probe_answers": {
                    probe["probe_id"]: probe["expected_prefix"] for probe in chunk["probes"]
                },
                "candidates": [
                    {
                        "local_id": "A",
                        "claim": "Niedozwolone automatyczne połączenie niezależnych regionów strony",
                        "page": page_label,
                        "quote": page.body,
                        "category": "OPEN_DISCOVERY",
                        "k0_target": "OUTSIDE_K0",
                        "film_value": 3,
                        "risk": 3,
                        "speaker_mode": "FACT_IN_SOURCE",
                        "genealogy": "fixture",
                        "facts": [],
                    }
                ],
                "metrics": {
                    "model": "fixture",
                    "effort": "low",
                    "measurement": "MEASURED",
                    "input_tokens": 1,
                    "cached_input_tokens": 0,
                    "output_tokens": 1,
                    "elapsed_ms": 1,
                    "retry": 0,
                },
            }
            incoming = self.run_dir / "incoming" / f"layout-{page_number}.json"
            incoming.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            with self.assertRaisesRegex(K1LiteV2Error, expected_code):
                import_worker_result(
                    isolation_root=self.root,
                    run_dir=self.run_dir,
                    result_path=incoming,
                    expected_ledger_sha="CREATE_NEW",
                )
        merged_columns = (
            "LEFT 1: independent left-column evidence.    "
            "RIGHT 1: independent right-column evidence."
        )
        self.assertIn(
            "QUOTE_JOINS_PARALLEL_COLUMNS",
            quote_pdf_layout_violations(self.pdf, 2, merged_columns),
        )
        ocr_body = document.pages[4].body
        self.assertEqual(quote_pdf_layout_violations(self.pdf, 5, ocr_body), [])

    def test_layout_mapping_tolerates_whitespace_only_differences(self) -> None:
        quote = "BODY  1:  Main  narrative  text  remains  in  the  upper  page  region."
        self.assertEqual(quote_pdf_layout_violations(self.pdf, 3, quote), [])
        partial_first_line = "Main narrative text remains in the upper page region."
        self.assertEqual(quote_pdf_layout_violations(self.pdf, 3, partial_first_line), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
