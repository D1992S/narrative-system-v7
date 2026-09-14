#!/usr/bin/env python3
"""Small fail-closed unit checks that are impractical through the PowerShell CLI."""

from __future__ import annotations

import importlib.util
import os
import sys
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
MODULE_PATH = HERE.parent / "pdf_to_markdown.py"
SPEC = importlib.util.spec_from_file_location("k1_lite_pdf_to_markdown", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
FIXTURE = Path(os.environ["K1_LITE_TEST_FIXTURE"]).resolve()


class FakeLargeDocument:
    is_pdf = True
    page_count = 10000
    needs_pass = False

    def __init__(self) -> None:
        self.closed = False

    def close(self) -> None:
        self.closed = True


class FailingReportHandle:
    def __init__(self, handle) -> None:
        self.handle = handle

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback) -> None:
        self.handle.close()

    def write(self, payload: bytes) -> int:
        self.handle.write(payload[:8])
        self.handle.flush()
        raise OSError("synthetic report write failure")


class K1LiteUnitTests(unittest.TestCase):
    def test_more_than_9999_pages_fails_closed(self) -> None:
        fake = FakeLargeDocument()
        with mock.patch.object(MODULE.fitz, "open", return_value=fake):
            with self.assertRaisesRegex(MODULE.K1LiteError, "PDF_PAGE_COUNT_UNSUPPORTED"):
                MODULE.open_pdf(Path("synthetic.pdf"))
        self.assertTrue(fake.closed)

    def test_pdf_rehash_blocks_write_when_source_changes_during_conversion(self) -> None:
        fixture = FIXTURE
        with tempfile.TemporaryDirectory(prefix="k1-lite-unit-") as temporary:
            root = Path(temporary)
            preview = root / "preview.md"
            report = root / "report.json"
            with (
                mock.patch.object(MODULE, "sha256_file", side_effect=["A" * 64, "B" * 64]),
                mock.patch.object(MODULE, "tesseract_languages", return_value=({"pol"}, "test")),
            ):
                with self.assertRaisesRegex(MODULE.K1LiteError, "PDF_CHANGED_DURING_CONVERSION"):
                    MODULE.render_preview(
                        pdf_path=fixture,
                        expected_pdf_sha256="A" * 64,
                        pages_to_ocr=[],
                        languages_text="none",
                        dpi=300,
                        psm=3,
                        tesseract="unused",
                        preview_path=preview,
                        report_path=report,
                        source_reference="sources/k1-lite-fixture.pdf",
                        preview_reference="_work/preview.md",
                    )
            self.assertFalse(preview.exists())
            self.assertFalse(report.exists())

    def test_tesseract_version_timeout_has_stable_error(self) -> None:
        list_result = subprocess.CompletedProcess(
            args=["tesseract", "--list-langs"],
            returncode=0,
            stdout="List of available languages:\npol\n",
            stderr="",
        )
        with mock.patch.object(
            MODULE.subprocess,
            "run",
            side_effect=[list_result, subprocess.TimeoutExpired(cmd="tesseract --version", timeout=30)],
        ):
            with self.assertRaisesRegex(MODULE.K1LiteError, "TESSERACT_UNAVAILABLE"):
                MODULE.tesseract_languages("tesseract")

    def test_partial_report_failure_removes_both_created_outputs(self) -> None:
        fixture = FIXTURE
        expected_sha = MODULE.sha256_file(fixture)
        real_path_open = Path.open
        with tempfile.TemporaryDirectory(prefix="k1-lite-unit-") as temporary:
            root = Path(temporary)
            preview = root / "preview.md"
            report = root / "report.json"

            def controlled_open(path: Path, mode: str = "r", *args, **kwargs):
                handle = real_path_open(path, mode, *args, **kwargs)
                if path == report and mode == "xb":
                    return FailingReportHandle(handle)
                return handle

            with (
                mock.patch.object(MODULE, "tesseract_languages", return_value=({"pol"}, "test")),
                mock.patch.object(Path, "open", autospec=True, side_effect=controlled_open),
            ):
                with self.assertRaisesRegex(OSError, "synthetic report write failure"):
                    MODULE.render_preview(
                        pdf_path=fixture,
                        expected_pdf_sha256=expected_sha,
                        pages_to_ocr=[],
                        languages_text="none",
                        dpi=300,
                        psm=3,
                        tesseract="unused",
                        preview_path=preview,
                        report_path=report,
                        source_reference="sources/k1-lite-fixture.pdf",
                        preview_reference="_work/preview.md",
                    )
            self.assertFalse(preview.exists())
            self.assertFalse(report.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
