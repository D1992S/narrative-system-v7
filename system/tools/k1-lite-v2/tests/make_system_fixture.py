#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from k1_lite_v2_core import (  # noqa: E402
    DECISION_BATCH_SCHEMA,
    EDITORIAL_REVIEW_RECEIPT_SCHEMA,
    VISUAL_RECEIPT_SCHEMA,
    WORKER_RESULT_SCHEMA,
    add_decisions,
    add_editorial_review_receipt,
    add_visual_receipt,
    build_views,
    import_worker_result,
    initialize_run,
    read_jsonl,
    sha256_bytes,
    sha256_file,
)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def make_result(run: dict, chunk: dict, candidates: list[dict]) -> dict:
    return {
        "schema": WORKER_RESULT_SCHEMA,
        "run_id": run["run_id"],
        "chunk_id": chunk["chunk_id"],
        "chunk_sha256": chunk["chunk_sha256"],
        "continuation_no": 0,
        "status": "CANDIDATE" if candidates else "SCANNED_NO_CANDIDATE",
        "more_strong_candidates": False,
        "probe_answers": {item["probe_id"]: item["expected_prefix"] for item in chunk["probes"]},
        "candidates": candidates,
        "metrics": {
            "model": "gpt-5.6-luna",
            "effort": "medium",
            "measurement": "MEASURED",
            "input_tokens": 300,
            "cached_input_tokens": 0,
            "output_tokens": 80,
            "elapsed_ms": 200,
            "retry": 0,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--run-name", default="fixture-run")
    parser.add_argument("--candidate", choices=("first", "second"), default="first")
    parser.add_argument("--source-stem", default="book")
    parser.add_argument("--source-kind", choices=("pdf", "md", "txt", "srt", "vtt"), default="pdf")
    parser.add_argument("--omit-review", action="store_true")
    args = parser.parse_args()
    project = args.project.resolve()
    sources = project / "sources"
    sources.mkdir(parents=True, exist_ok=True)

    body = (
        "CHAPTER 1\n"
        "The source states that the test event happened in 7640 bc.\n"
        "Context remains attached to the exact quotation.\n"
        "A second passage says the witness recorded the event before sunrise."
    )
    pdf: Path | None = None
    pdf_sha: str | None = None
    if args.source_kind == "pdf":
        import fitz

        pdf = sources / f"{args.source_stem}.pdf"
        if not pdf.exists():
            document = fitz.open()
            page = document.new_page()
            page.insert_textbox(page.rect + (40, 40, -40, -40), body, fontsize=10)
            document.save(pdf)
            document.close()
        pdf_sha = sha256_file(pdf)
        page_hash = sha256_bytes((body + "\n").encode("utf-8"))
        source = sources / f"{args.source_stem}--TEXT.md"
        if not source.exists():
            source.write_text(
                "---\nPDF_TEXT_SCHEMA: K1_LITE_PDF_TEXT_V1\n"
                f'ORIGINAL_PDF: "sources/{args.source_stem}.pdf"\n'
                f"ORIGINAL_PDF_SHA256: {pdf_sha}\nPHYSICAL_PAGES: 1\nOCR_LANGUAGES: none\nOCR_ENGINE: tesseract\n---\n\n"
                f"<!-- PDF_PAGE_BEGIN: P0001; METHOD: NATIVE; PAGE_TEXT_SHA256: {page_hash}; FLAGS: NONE -->\n"
                f"{body}\n<!-- PDF_PAGE_END: P0001 -->\n",
                encoding="utf-8",
            )
    elif args.source_kind in {"md", "txt"}:
        source = sources / f"{args.source_stem}.{args.source_kind}"
        if not source.exists():
            source.write_text(body + "\n", encoding="utf-8")
    elif args.source_kind == "srt":
        source = sources / f"{args.source_stem}.srt"
        if not source.exists():
            source.write_text(
                "1\n00:00:01,000 --> 00:00:05,000\nThe source states that the test event happened in 7640 bc.\n\n"
                "2\n00:00:06,000 --> 00:00:10,000\nContext remains attached to the exact quotation.\n\n"
                "3\n00:00:11,000 --> 00:00:15,000\nA second passage says the witness recorded the event before sunrise.\n",
                encoding="utf-8",
            )
    else:
        source = sources / f"{args.source_stem}.vtt"
        if not source.exists():
            source.write_text(
                "WEBVTT\n\n00:00:01.000 --> 00:00:05.000\nThe source states that the test event happened in 7640 bc.\n\n"
                "00:00:06.000 --> 00:00:10.000\nContext remains attached to the exact quotation.\n\n"
                "00:00:11.000 --> 00:00:15.000\nA second passage says the witness recorded the event before sunrise.\n",
                encoding="utf-8",
            )
    foundation = project / "00-fundament-projektu.md"
    if not foundation.exists():
        foundation.write_text(
        "# 00\nSTATUS: GOTOWY\nZGODNOŚĆ_Z_W0: TAK\n"
        "- PYTANIE GŁÓWNE: Co wydarzyło się w teście?\n"
        "- OBIETNICA: Odpowiedź źródłowa.\n- KONFLIKT/NAPIĘCIE: Różnica interpretacji.\n"
        "- W FILMIE: Test.\n- POZA FILMEM: Inne tematy.\n- WĄTKI OBOWIĄZKOWE: Data.\n"
        "- TEMAT ANALIZY K1-LITE V2: data zdarzenia\n"
        "| ID | Pytanie badawcze | Co zmieni odpowiedź | Minimalny warunek pokrycia | Priorytet | Hasła wyszukiwania |\n"
        "|---|---|---|---|---|---|\n| Q-001 | Jaka data? | Oś czasu | Jeden cytat | MUST | date |\n"
        "- TRYB RESEARCHU: SOURCES_ONLY\n- ZGODA NA WEB: NIE\n- POLITYKA WERYFIKACJI: SOURCE_FIRST_K4\n",
            encoding="utf-8",
        )
    meta = project / "meta.md"
    if not meta.exists():
        meta.write_text(
        "# META PROJEKTU\nSYSTEM_VERSION: 7.0\nWORKFLOW_REVISION: 2026-08-30_K1_LITE_V2\n"
        "EVIDENCE_SCHEMA: MINIMAL_EVIDENCE_V4_PAGELOC\nPROJECT_NAME: fixture\n"
        f"PROJECT_PATH: {project}\nCURRENT_STAGE: K1\nSTAGE_OWNER: ChatGPT\nOWNER_OVERRIDE: BRAK\n"
        "W0_DECISION: GO\nCHANNEL: TEST\nFORMAT: dokument\nTARGET_MINUTES: 10\nREAL_WPM: 130\nWPM_STATUS: ZAŁOŻENIE\n"
        "RESEARCH_MODE: SOURCES_ONLY\nVERIFICATION_POLICY: SOURCE_FIRST_K4\nK1_RESEARCH_MODE: K1_LITE_V2\n"
        "K1_ENGINE_VERSION: 2.1.0\nK1_RUN_PATH: BRAK\nK1_LEDGER_SHA256: BRAK\nK1_MANUAL_REASON: BRAK\n"
        "REFERENCE_SCRIPT: BRAK\nK2B_DECISION: NIEUSTALONE\nLAST_GATE: K0_PASS\nLAST_UPDATED: 2026-08-30\nNEXT_ACTION: K1\n",
            encoding="utf-8",
        )

    origin = project / ".system-v7" / "project-origin.json"
    if not origin.exists():
        meta_text = meta.read_text(encoding="utf-8")
        project_name_match = re.search(r"(?m)^PROJECT_NAME:\s*(.*?)\s*$", meta_text)
        if not project_name_match:
            raise RuntimeError("PROJECT_NAME_MISSING_FOR_FIXTURE_ORIGIN")
        project_name = project_name_match.group(1).strip()
        project_id = "00000000-0000-4000-8000-" + hashlib.sha256(str(project).encode("utf-8")).hexdigest()[:12]
        now = datetime.now(timezone.utc)
        created_at = now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond:06d}0Z"
        binding = (
            "SCHEMA=SYSTEM_V7_PROJECT_ORIGIN_V1\n"
            f"PROJECT_ID={project_id}\nPROJECT_NAME={project_name}\nPROJECT_PATH={project}\n"
            f"CREATED_AT_UTC={created_at}\nSYSTEM_VERSION=7.0\n"
            "WORKFLOW_REVISION=2026-08-30_K1_LITE_V2\n"
            "EVIDENCE_SCHEMA=MINIMAL_EVIDENCE_V4_PAGELOC\n"
        )
        origin_record = {
            "schema": "SYSTEM_V7_PROJECT_ORIGIN_V1",
            "project_id": project_id,
            "project_name": project_name,
            "project_path": str(project),
            "created_at_utc": created_at,
            "system_version": "7.0",
            "origin_workflow_revision": "2026-08-30_K1_LITE_V2",
            "origin_evidence_schema": "MINIMAL_EVIDENCE_V4_PAGELOC",
            "binding_sha256": hashlib.sha256(binding.encode("utf-8")).hexdigest().upper(),
        }
        write_json(origin, origin_record)

    run_dir = project / "_work" / "K1" / "k1-lite-v2" / args.run_name
    run = initialize_run(
        isolation_root=project,
        source_path=source,
        expected_source_sha=sha256_file(source),
        pdf_path=pdf,
        expected_pdf_sha=pdf_sha,
        run_dir=run_dir,
        k0_path=project / "00-fundament-projektu.md",
        expected_k0_sha=sha256_file(project / "00-fundament-projektu.md"),
        target_min=1000,
        target_max=4000,
    )
    chunks = read_jsonl(run_dir / "chunks.jsonl")
    ledger_sha = "CREATE_NEW"
    candidate_id = ""
    quote_sha = ""
    for index, chunk in enumerate(chunks):
        candidates = []
        if index == 0:
            quote = (
                "The source states that the test event happened in 7640 bc."
                if args.candidate == "first"
                else "A second passage says the witness recorded the event before sunrise."
            )
            claim = "Źródło podaje datę zdarzenia." if args.candidate == "first" else "Źródło opisuje porę zapisu świadka."
            candidates = [{
                "local_id": "A", "claim": claim, "page": "P0001",
                "quote": quote,
                "category": "TARGETED", "k0_target": "Q-001", "film_value": 3, "risk": 1,
                "speaker_mode": "AUTHOR_CLAIM", "genealogy": "Bezpośrednie twierdzenie źródła.",
                "facts": [{"key": "event_date", "value": "7640 bc", "subject_terms": ["event", "happened"]}],
            }]
        result_path = run_dir / "incoming" / f"{chunk['chunk_id']}.json"
        write_json(result_path, make_result(run, chunk, candidates))
        imported = import_worker_result(isolation_root=project, run_dir=run_dir, result_path=result_path, expected_ledger_sha=ledger_sha)
        ledger_sha = imported["ledger_sha256"]
    candidate = next(item for item in read_jsonl(run_dir / "ledger.jsonl") if item.get("event_type") == "candidate")
    candidate_id = candidate["candidate_id"]
    quote_sha = candidate["quote_sha256"]
    decision_path = run_dir / "incoming" / "recommendation.json"
    write_json(decision_path, {"schema": DECISION_BATCH_SCHEMA, "run_id": run["run_id"], "decisions": [{
        "candidate_id": candidate_id, "decision": "KEY_CHATGPT", "actor": "CHATGPT",
        "reason": "Kluczowy dowód testowy.", "conflict_acknowledged": False,
    }]})
    ledger_sha = add_decisions(isolation_root=project, run_dir=run_dir, decision_path=decision_path, expected_ledger_sha=ledger_sha)["ledger_sha256"]
    editorial_path = run_dir / "incoming" / "dawid-decision.json"
    write_json(editorial_path, {"schema": DECISION_BATCH_SCHEMA, "run_id": run["run_id"], "decisions": [{
        "candidate_id": candidate_id, "decision": "MUST_INCLUDE", "actor": "DAWID",
        "reason": "Dawid zatwierdza kandydat i jawnie rozstrzyga ewentualny konflikt.",
        "conflict_acknowledged": True,
    }]})
    ledger_sha = add_decisions(
        isolation_root=project,
        run_dir=run_dir,
        decision_path=editorial_path,
        expected_ledger_sha=ledger_sha,
    )["ledger_sha256"]
    if args.source_kind == "pdf":
        full = run_dir / "qa" / "full.png"
        crop = run_dir / "qa" / "crop.png"
        full.parent.mkdir(parents=True, exist_ok=True)
        full.write_bytes(b"full")
        crop.write_bytes(b"crop")
        receipt = run_dir / "incoming" / "visual.json"
        write_json(receipt, {"schema": VISUAL_RECEIPT_SCHEMA, "run_id": run["run_id"], "candidate_id": candidate_id,
            "quote_sha256": quote_sha, "full_render_relative": full.relative_to(project).as_posix(),
            "full_render_sha256": sha256_file(full), "crop_relative": crop.relative_to(project).as_posix(),
            "crop_sha256": sha256_file(crop), "reviewer": "fixture-controller", "verdict": "PASS"})
        ledger_sha = add_visual_receipt(isolation_root=project, run_dir=run_dir, receipt_path=receipt, expected_ledger_sha=ledger_sha)["ledger_sha256"]
    if not args.omit_review:
        review_view = run_dir / "views" / "fixture-editorial-review"
        report = build_views(isolation_root=project, run_dir=run_dir, output_dir=review_view)
        artifact = review_view / "editorial-review.md"
        review_receipt = run_dir / "incoming" / "editorial-review.json"
        write_json(review_receipt, {
            "schema": EDITORIAL_REVIEW_RECEIPT_SCHEMA,
            "run_id": run["run_id"],
            "snapshot_sha256": report["editorial_review"]["snapshot_sha256"],
            "review_artifact_relative": artifact.relative_to(run_dir).as_posix(),
            "review_artifact_sha256": sha256_file(artifact),
            "actor": "DAWID",
            "verdict": "REVIEWED",
            "note": "Dawid przejrzał fixture najmocniejszych i ryzykownych kandydatów.",
        })
        ledger_sha = add_editorial_review_receipt(
            isolation_root=project,
            run_dir=run_dir,
            receipt_path=review_receipt,
            expected_ledger_sha=ledger_sha,
        )["ledger_sha256"]
    print(json.dumps({"project": str(project), "run_dir": str(run_dir), "ledger_sha256": ledger_sha, "source_kind": args.source_kind}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
