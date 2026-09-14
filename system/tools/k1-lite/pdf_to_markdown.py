#!/usr/bin/env python3
"""Deterministic, page-preserving PDF inspection and PDF-to-Markdown preview."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import shutil
from page_cache import PageCache
from pathlib import Path

try:
    import fitz
except Exception as exc:  # pragma: no cover - explicit preflight error
    raise SystemExit(f"PYMUPDF_MISSING: {exc}") from exc


SCHEMA = "K1_LITE_PDF_TEXT_V1"
REPORT_SCHEMA = "K1_LITE_CONVERSION_REPORT_V1"
RESERVED_MARKER = re.compile(r"^<!-- PDF_PAGE_(?:BEGIN|END):", re.MULTILINE)


class K1LiteError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest().upper()


def normalize_page_text(value: str) -> str:
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    lines = [line.rstrip(" \t") for line in value.split("\n")]
    while lines and lines[0] == "":
        lines.pop(0)
    while lines and lines[-1] == "":
        lines.pop()
    if not lines:
        return ""
    normalized = "\n".join(lines) + "\n"
    if RESERVED_MARKER.search(normalized):
        raise K1LiteError("RESERVED_MARKER_IN_SOURCE: source text contains a reserved marker line")
    return normalized


def open_pdf(path: Path) -> fitz.Document:
    try:
        document = fitz.open(path)
    except Exception as exc:
        raise K1LiteError(f"PDF_OPEN_FAILED: {exc}") from exc
    if not document.is_pdf or document.page_count < 1:
        document.close()
        raise K1LiteError("PDF_INVALID: input is not a non-empty PDF")
    if document.needs_pass:
        document.close()
        raise K1LiteError("PDF_ENCRYPTED: password-protected PDF is not supported")
    if document.page_count > 9999:
        document.close()
        raise K1LiteError(f"PDF_PAGE_COUNT_UNSUPPORTED: pages={document.page_count} max=9999")
    return document


def native_text(page: fitz.Page) -> str:
    return page.get_text("text", sort=True)


def non_whitespace_count(value: str) -> int:
    return sum(1 for char in value if not char.isspace())


def inspect_pdf(path: Path, threshold: int) -> dict:
    document = open_pdf(path)
    try:
        pages = []
        suggestions = []
        for number, page in enumerate(document, start=1):
            count = non_whitespace_count(native_text(page))
            suggested = count < threshold
            pages.append(
                {
                    "page": number,
                    "native_non_whitespace_chars": count,
                    "suggested_ocr": suggested,
                }
            )
            if suggested:
                suggestions.append(number)
        return {
            "schema": "K1_LITE_INSPECTION_V1",
            "source_pdf": str(path),
            "pdf_sha256": sha256_file(path),
            "pdf_pages": document.page_count,
            "native_text_threshold": threshold,
            "ocr_suggestions": suggestions,
            "pages": pages,
        }
    finally:
        document.close()


def parse_page_list(value: str) -> list[int]:
    if value == "" or value.upper() == "NONE":
        return []
    values: list[int] = []
    for token in value.split(","):
        if not token.isdigit():
            raise K1LiteError("OCR_PAGES_INVALID")
        number = int(token)
        if number < 1:
            raise K1LiteError("OCR_PAGES_INVALID")
        values.append(number)
    if len(values) != len(set(values)):
        raise K1LiteError("OCR_PAGES_DUPLICATE")
    return sorted(values)


def requested_languages(value: str) -> list[str]:
    languages = value.split("+") if value else []
    if not languages or any(not re.fullmatch(r"[a-z0-9_]+", item) for item in languages):
        raise K1LiteError("OCR_LANGUAGES_INVALID")
    if "osd" in languages:
        raise K1LiteError("OCR_LANGUAGE_INVALID: osd is not a content language")
    return languages


def tesseract_languages(executable: str) -> tuple[set[str], str]:
    try:
        listed = subprocess.run(
            [executable, "--list-langs"],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise K1LiteError(f"TESSERACT_UNAVAILABLE: {exc}") from exc
    if listed.returncode != 0:
        raise K1LiteError(f"TESSERACT_UNAVAILABLE: {listed.stderr.strip()}")
    languages = {line.strip() for line in listed.stdout.splitlines() if re.fullmatch(r"[A-Za-z0-9_]+", line.strip())}
    try:
        version_run = subprocess.run(
            [executable, "--version"],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise K1LiteError(f"TESSERACT_UNAVAILABLE: {exc}") from exc
    first_line = (version_run.stdout or version_run.stderr).splitlines()[0] if (version_run.stdout or version_run.stderr) else "unknown"
    version = first_line.replace("tesseract", "", 1).strip()
    return languages, version


def ocr_page(page: fitz.Page, *, executable: str, languages: str, dpi: int, psm: int, temp_dir: Path) -> str:
    scale = dpi / 72.0
    pixmap = page.get_pixmap(matrix=fitz.Matrix(scale, scale), alpha=False, colorspace=fitz.csRGB)
    image_path = temp_dir / f"page-{page.number + 1:04d}.png"
    pixmap.save(image_path)
    try:
        completed = subprocess.run(
            [executable, str(image_path), "stdout", "-l", languages, "--dpi", str(dpi), "--psm", str(psm)],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=300,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise K1LiteError(f"OCR_FAILED_PAGE_{page.number + 1:04d}: {exc}") from exc
    if completed.returncode != 0:
        detail = completed.stderr.strip() or f"exit={completed.returncode}"
        raise K1LiteError(f"OCR_FAILED_PAGE_{page.number + 1:04d}: {detail}")
    return completed.stdout


def yaml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def render_preview(
    *,
    pdf_path: Path,
    expected_pdf_sha256: str,
    pages_to_ocr: list[int],
    languages_text: str,
    dpi: int,
    psm: int,
    tesseract: str,
    preview_path: Path,
    report_path: Path,
    source_reference: str,
    preview_reference: str,
    cache_path: Path | None = None,
) -> dict:
    actual_pdf_sha = sha256_file(pdf_path)
    if actual_pdf_sha != expected_pdf_sha256.upper():
        raise K1LiteError(f"PDF_HASH_MISMATCH: expected={expected_pdf_sha256.upper()} actual={actual_pdf_sha}")
    if preview_path.exists() or report_path.exists():
        raise K1LiteError("PREVIEW_OUTPUT_EXISTS")

    if pages_to_ocr:
        languages = requested_languages(languages_text)
        available_languages, tesseract_version = tesseract_languages(tesseract)
        missing = [item for item in languages if item not in available_languages]
        if missing:
            raise K1LiteError("OCR_LANGUAGE_MISSING: " + ",".join(missing))
    else:
        if languages_text.lower() != "none":
            raise K1LiteError("OCR_LANGUAGES_MUST_BE_NONE")
        languages = []
        tesseract_version = "not_used"

    written_keys = []
    cache_base = {'pdf': actual_pdf_sha, 'converter': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  'pymupdf': fitz.VersionBind}
    ocr_identity = None
    if pages_to_ocr:
        # Model bytes are part of identity; unknown location disables OCR reuse.
        listing = subprocess.run([tesseract, '--list-langs'], capture_output=True, text=True)
        match = re.search(r'"([^"\n]+)"', listing.stdout + listing.stderr)
        executable = shutil.which(tesseract)
        if match and executable:
            model_root = Path(match.group(1))
            model_languages = list(languages) + (['osd'] if psm in (1, 12) and 'osd' not in languages else [])
            models = [model_root / (lang + '.traineddata') for lang in model_languages]
            if all(p.is_file() for p in models):
                ocr_identity = {'executable': sha256_file(Path(executable)),
                                'models': [sha256_file(p) for p in models],
                                'version': tesseract_version, 'languages': languages_text,
                                'dpi': dpi, 'psm': psm}
    document = open_pdf(pdf_path)
    cache = PageCache(cache_path or preview_path.parent / 'page-cache.sqlite3')
    try:
        if any(page_number > document.page_count for page_number in pages_to_ocr):
            raise K1LiteError(f"OCR_PAGE_OUT_OF_RANGE: pages={document.page_count}")
        page_set = set(pages_to_ocr)
        blocks: list[str] = []
        with tempfile.TemporaryDirectory(prefix="k1-lite-ocr-") as temporary:
            temporary_path = Path(temporary)
            for number, page in enumerate(document, start=1):
                is_ocr = number in page_set
                method = 'OCR' if is_ocr else 'NATIVE'
                flags = 'LAYOUT_REVIEW_REQUIRED' if is_ocr else 'NONE'
                key = PageCache.key({**cache_base, 'page': number, 'method': method,
                                     'ocr': ocr_identity if is_ocr else None})
                reusable = not is_ocr or ocr_identity is not None
                body = cache.get(key) if reusable else None
                if body is None:
                    extracted = ocr_page(page, executable=tesseract, languages=languages_text,
                                         dpi=dpi, psm=psm, temp_dir=temporary_path) if is_ocr else native_text(page)
                    body = normalize_page_text(extracted)
                    if reusable:
                        cache.put(key, body)
                        written_keys.append(key)
                page_hash = sha256_bytes(body.encode("utf-8"))
                label = f"P{number:04d}"
                begin = (
                    f"<!-- PDF_PAGE_BEGIN: {label}; METHOD: {method}; "
                    f"PAGE_TEXT_SHA256: {page_hash}; FLAGS: {flags} -->\n"
                )
                end = f"<!-- PDF_PAGE_END: {label} -->\n"
                blocks.append(begin + body + end)

        final_pdf_sha = sha256_file(pdf_path)
        if final_pdf_sha != actual_pdf_sha:
            raise K1LiteError(f"PDF_CHANGED_DURING_CONVERSION: before={actual_pdf_sha} after={final_pdf_sha}")

        frontmatter = (
            "---\n"
            f"PDF_TEXT_SCHEMA: {SCHEMA}\n"
            f"ORIGINAL_PDF: {yaml_string(source_reference)}\n"
            f"ORIGINAL_PDF_SHA256: {actual_pdf_sha}\n"
            f"PHYSICAL_PAGES: {document.page_count}\n"
            f"OCR_LANGUAGES: {languages_text}\n"
            "OCR_ENGINE: tesseract\n"
            "---\n\n"
        )
        preview_bytes = (frontmatter + "\n".join(blocks)).encode("utf-8")
        preview_sha = sha256_bytes(preview_bytes)
        report = {
            "schema": REPORT_SCHEMA,
            "source_pdf": source_reference,
            "pdf_sha256": actual_pdf_sha,
            "pdf_pages": document.page_count,
            "preview_path": preview_reference,
            "preview_sha256": preview_sha,
            "native_pages": document.page_count - len(page_set),
            "ocr_pages": pages_to_ocr,
            "ocr_languages": languages,
            "ocr_dpi": dpi,
            "psm": psm,
            "page_cache": {"hits": cache.hits, "misses": cache.misses, "error": cache.error, "ocr_reuse_available": ocr_identity is not None},
            "tool_versions": {"pymupdf": fitz.VersionBind, "tesseract": tesseract_version},
        }
        report_bytes = (json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode("utf-8")

        preview_path.parent.mkdir(parents=True, exist_ok=True)
        created_preview = False
        created_report = False
        try:
            with preview_path.open("xb") as preview_handle:
                created_preview = True
                preview_handle.write(preview_bytes)
            with report_path.open("xb") as report_handle:
                created_report = True
                report_handle.write(report_bytes)
        except Exception:
            if created_report and report_path.exists():
                report_path.unlink()
            if created_preview and preview_path.exists():
                preview_path.unlink()
            raise
        return report
    finally:
        document.close()
        # A changed or vanished input must not leave reusable partial pages.
        try:
            with pdf_path.open('rb') as handle:
                unchanged = hashlib.file_digest(handle, 'sha256').hexdigest().upper() == actual_pdf_sha
        except OSError:
            unchanged = False
        if not unchanged:
            cache.discard(written_keys)
        cache.close()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect = subparsers.add_parser("inspect")
    inspect.add_argument("--pdf", required=True, type=Path)
    inspect.add_argument("--threshold", type=int, default=80)

    preview = subparsers.add_parser("preview")
    preview.add_argument("--cache", type=Path)
    preview.add_argument("--pdf", required=True, type=Path)
    preview.add_argument("--expected-pdf-sha256", required=True)
    preview.add_argument("--ocr-pages", required=True)
    preview.add_argument("--ocr-languages", required=True)
    preview.add_argument("--dpi", required=True, type=int)
    preview.add_argument("--psm", required=True, type=int)
    preview.add_argument("--tesseract", required=True)
    preview.add_argument("--preview", required=True, type=Path)
    preview.add_argument("--report", required=True, type=Path)
    preview.add_argument("--source-reference", required=True)
    preview.add_argument("--preview-reference", required=True)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "inspect":
            if not (0 <= args.threshold <= 1_000_000):
                raise K1LiteError("NATIVE_TEXT_THRESHOLD_INVALID")
            result = inspect_pdf(args.pdf.resolve(strict=True), args.threshold)
        else:
            if not re.fullmatch(r"[0-9A-Fa-f]{64}", args.expected_pdf_sha256):
                raise K1LiteError("EXPECTED_PDF_SHA_INVALID")
            if not (150 <= args.dpi <= 600):
                raise K1LiteError("OCR_DPI_INVALID")
            if not (1 <= args.psm <= 13):
                raise K1LiteError("OCR_PSM_INVALID")
            result = render_preview(
                pdf_path=args.pdf.resolve(strict=True),
                expected_pdf_sha256=args.expected_pdf_sha256,
                pages_to_ocr=parse_page_list(args.ocr_pages),
                languages_text=args.ocr_languages,
                dpi=args.dpi,
                psm=args.psm,
                tesseract=args.tesseract,
                preview_path=args.preview.resolve(strict=False),
                report_path=args.report.resolve(strict=False),
                cache_path=args.cache,
                source_reference=args.source_reference,
                preview_reference=args.preview_reference,
            )
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (K1LiteError, FileNotFoundError, PermissionError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
