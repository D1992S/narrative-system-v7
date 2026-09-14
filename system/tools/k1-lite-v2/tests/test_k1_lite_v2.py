#!/usr/bin/env python3
"""Regression tests for the isolated K1-Lite V2 analysis layer."""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from k1_lite_v2_core import (  # noqa: E402
    DECISION_BATCH_SCHEMA,
    EDITORIAL_REVIEW_RECEIPT_SCHEMA,
    VISUAL_RECEIPT_SCHEMA,
    WORKER_RESULT_SCHEMA,
    K1LiteV2Error,
    Page,
    SourceDocument,
    add_decisions,
    add_editorial_review_receipt,
    add_visual_receipt,
    build_views,
    compare_text_twins,
    find_quote,
    find_conflicts,
    import_worker_result,
    initialize_run,
    inspect_pdf_layout,
    latest_editorial_decisions,
    latest_recommendations,
    make_analysis_brief,
    read_jsonl,
    read_source,
    sha256_bytes,
    sha256_file,
    selected_candidates,
    stale_active_state,
    validate_run,
    verify_quote_batch,
)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def page_body(title: str, special: str) -> str:
    filler = " ".join(["Tekst źródłowy zachowuje pełny kontekst i kolejność zdań."] * 18)
    return f"{title}\n{special}\n{filler}"


def build_k1_source(root: Path) -> tuple[Path, Path, list[str]]:
    pdf = root / "PROJECT" / "sources" / "book.pdf"
    pdf.parent.mkdir(parents=True)
    bodies = [
        page_body("CHAPTER 1", "The comet impact happened in 7640 bc near the northern coast."),
        page_body("CONTINUATION", "A later summary calls the same comet impact 7620 bc near the northern coast."),
        page_body("A p p e n d i x 3", "Appendix three is content and must not be skipped."),
        page_body("APPENDIX CONTINUATION", "The appendix continues with substantive evidence."),
        page_body("A p p e n d i x 4", "Rosslyn Chapel remains substantive source content."),
        page_body("BIBLIOGRAPHY", "Reference list begins only on this physical page."),
        page_body("INDEX", "Index entries remain covered as reference chunks."),
    ]
    import fitz

    pdf_document = fitz.open()
    for body in bodies:
        page = pdf_document.new_page()
        page.insert_textbox(page.rect + (40, 40, -40, -40), body, fontsize=8)
    pdf_document.save(pdf)
    pdf_document.close()
    pdf_sha = sha256_file(pdf)
    blocks: list[str] = []
    for number, body in enumerate(bodies, start=1):
        page_hash = sha256_bytes((body + "\n").encode("utf-8"))
        blocks.append(
            f"<!-- PDF_PAGE_BEGIN: P{number:04d}; METHOD: NATIVE; PAGE_TEXT_SHA256: {page_hash}; FLAGS: NONE -->\n"
            f"{body}\n"
            f"<!-- PDF_PAGE_END: P{number:04d} -->\n"
        )
    source = root / "PROJECT" / "sources" / "book--TEXT.md"
    source.write_text(
        "---\n"
        "PDF_TEXT_SCHEMA: K1_LITE_PDF_TEXT_V1\n"
        'ORIGINAL_PDF: "sources/book.pdf"\n'
        f"ORIGINAL_PDF_SHA256: {pdf_sha}\n"
        f"PHYSICAL_PAGES: {len(bodies)}\n"
        "OCR_LANGUAGES: none\n"
        "OCR_ENGINE: tesseract\n"
        "---\n\n"
        + "\n".join(blocks),
        encoding="utf-8",
    )
    return source, pdf, bodies


def make_result(run: dict, chunk: dict, *, candidates: list[dict], continuation: int = 0, more: bool = False) -> dict:
    return {
        "schema": WORKER_RESULT_SCHEMA,
        "run_id": run["run_id"],
        "chunk_id": chunk["chunk_id"],
        "chunk_sha256": chunk["chunk_sha256"],
        "continuation_no": continuation,
        "status": "PARTIAL_OVERFLOW" if more else ("CANDIDATE" if candidates else "SCANNED_NO_CANDIDATE"),
        "more_strong_candidates": more,
        "probe_answers": {item["probe_id"]: item["expected_prefix"] for item in chunk["probes"]} if continuation == 0 else {},
        "candidates": candidates,
        "metrics": {
            "model": "gpt-5.6-luna",
            "effort": "medium",
            "measurement": "MEASURED",
            "input_tokens": 1200,
            "cached_input_tokens": 100,
            "output_tokens": 180,
            "elapsed_ms": 900,
            "retry": 0,
        },
    }


def add_current_editorial_review(
    root: Path, run_dir: Path, run: dict, ledger_sha: str, name: str
) -> tuple[str, dict, Path]:
    view_dir = run_dir / "views" / name
    report = build_views(isolation_root=root, run_dir=run_dir, output_dir=view_dir)
    artifact = view_dir / "editorial-review.md"
    receipt = run_dir / "incoming" / f"{name}-editorial-review.json"
    write_json(
        receipt,
        {
            "schema": EDITORIAL_REVIEW_RECEIPT_SCHEMA,
            "run_id": run["run_id"],
            "snapshot_sha256": report["editorial_review"]["snapshot_sha256"],
            "review_artifact_relative": artifact.relative_to(run_dir).as_posix(),
            "review_artifact_sha256": sha256_file(artifact),
            "actor": "DAWID",
            "verdict": "REVIEWED",
            "note": "Dawid przejrzał aktualną listę najmocniejszych i ryzykownych wątków.",
        },
    )
    appended = add_editorial_review_receipt(
        isolation_root=root,
        run_dir=run_dir,
        receipt_path=receipt,
        expected_ledger_sha=ledger_sha,
    )
    return appended["ledger_sha256"], report, artifact


class K1LiteV2Tests(unittest.TestCase):
    def test_run_directory_must_use_project_k1_root(self):
        with self.assertRaisesRegex(K1LiteV2Error, "PATH_OUTSIDE_ISOLATION"):
            initialize_run(
                isolation_root=self.root,
                source_path=self.source,
                expected_source_sha=sha256_file(self.source),
                pdf_path=self.pdf,
                expected_pdf_sha=sha256_file(self.pdf),
                run_dir=self.root / "other" / "run",
                k0_path=None,
                expected_k0_sha=None,
                target_min=1000,
                target_max=4000,
            )

    def test_moved_run_is_rejected_by_later_actions(self):
        moved_run = self.root / "moved" / "run-001"
        shutil.copytree(self.run_dir, moved_run)
        with self.assertRaisesRegex(K1LiteV2Error, "PATH_OUTSIDE_ISOLATION"):
            validate_run(isolation_root=self.root, run_dir=moved_run)

    def test_superseded_candidate_decision_remains_history_not_stale(self):
        candidates = {"C-NEW": {"quote_sha256": "B" * 64}}
        state = {
            "C-OLD": {"candidate_quote_sha256": "A" * 64},
            "C-NEW": {"candidate_quote_sha256": "B" * 64},
        }
        self.assertEqual(stale_active_state(candidates, state), [])
        state["C-NEW"]["candidate_quote_sha256"] = "C" * 64
        self.assertEqual(stale_active_state(candidates, state), ["C-NEW"])

    def test_chatgpt_recommendation_and_dawid_decision_are_independent(self):
        ledger = [
            {"event_type": "decision", "candidate_id": "C0001-00-A", "decision": "KEY_CHATGPT"},
            {"event_type": "decision", "candidate_id": "C0001-00-A", "decision": "REJECTED"},
        ]
        candidates = {"C0001-00-A": {"quote_sha256": "A" * 64}}
        decisions = latest_editorial_decisions(ledger)
        recommendations = latest_recommendations(ledger)
        self.assertEqual(decisions["C0001-00-A"]["decision"], "REJECTED")
        self.assertEqual(recommendations["C0001-00-A"]["decision"], "KEY_CHATGPT")
        self.assertNotIn("C0001-00-A", selected_candidates(candidates, decisions, recommendations))

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="k1-lite-v2-test-")
        self.root = Path(self.temporary.name).resolve()
        self.source, self.pdf, self.bodies = build_k1_source(self.root)
        self.run_dir = self.root / "_work" / "K1" / "k1-lite-v2" / "run-001"
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
        self.chunks = read_jsonl(self.run_dir / "chunks.jsonl")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _complete_coverage_with_one_candidate(self) -> tuple[str, dict]:
        ledger_sha = "CREATE_NEW"
        candidate_record: dict | None = None
        target_chunk = next(chunk for chunk in self.chunks if "P0005" in chunk["pages"])
        for chunk in self.chunks:
            candidates = []
            if chunk["chunk_id"] == target_chunk["chunk_id"]:
                candidates = [{
                    "local_id": "A",
                    "claim": "Kaplica Rosslyn pozostaje istotnym wątkiem źródłowym",
                    "page": "P0005",
                    "quote": "Rosslyn Chapel remains substantive source content.",
                    "category": "OPEN_DISCOVERY",
                    "k0_target": "OUTSIDE_K0",
                    "film_value": 3,
                    "risk": 2,
                    "speaker_mode": "AUTHOR_CLAIM",
                    "genealogy": "source",
                    "facts": [],
                }]
            result_path = self.run_dir / "incoming" / f"helper-{chunk['chunk_id']}.json"
            write_json(result_path, make_result(self.run, chunk, candidates=candidates))
            ledger_sha = import_worker_result(
                isolation_root=self.root,
                run_dir=self.run_dir,
                result_path=result_path,
                expected_ledger_sha=ledger_sha,
            )["ledger_sha256"]
        candidate_record = next(
            item for item in read_jsonl(self.run_dir / "ledger.jsonl") if item.get("event_type") == "candidate"
        )
        return ledger_sha, candidate_record

    def test_key_chatgpt_cannot_acknowledge_a_conflict(self) -> None:
        ledger_sha, candidate = self._complete_coverage_with_one_candidate()
        decision_file = self.run_dir / "incoming" / "invalid-chatgpt-ack.json"
        write_json(decision_file, {
            "schema": DECISION_BATCH_SCHEMA,
            "run_id": self.run["run_id"],
            "decisions": [{
                "candidate_id": candidate["candidate_id"],
                "decision": "KEY_CHATGPT",
                "actor": "CHATGPT",
                "reason": "Rekomendacja nie może rozstrzygać konfliktu.",
                "conflict_acknowledged": True,
            }],
        })
        with self.assertRaisesRegex(K1LiteV2Error, "KEY_CHATGPT_CONFLICT_ACK_FORBIDDEN"):
            add_decisions(
                isolation_root=self.root,
                run_dir=self.run_dir,
                decision_path=decision_file,
                expected_ledger_sha=ledger_sha,
            )

    def test_review_snapshot_ignores_visual_but_stales_after_decision(self) -> None:
        ledger_sha, candidate = self._complete_coverage_with_one_candidate()
        recommendation = self.run_dir / "incoming" / "key-chatgpt.json"
        write_json(recommendation, {
            "schema": DECISION_BATCH_SCHEMA,
            "run_id": self.run["run_id"],
            "decisions": [{
                "candidate_id": candidate["candidate_id"], "decision": "KEY_CHATGPT", "actor": "CHATGPT",
                "reason": "Najmocniejszy kandydat tego przebiegu.", "conflict_acknowledged": False,
            }],
        })
        ledger_sha = add_decisions(
            isolation_root=self.root, run_dir=self.run_dir, decision_path=recommendation,
            expected_ledger_sha=ledger_sha,
        )["ledger_sha256"]
        ledger_sha, _report, _artifact = add_current_editorial_review(
            self.root, self.run_dir, self.run, ledger_sha, "snapshot-base"
        )

        full = self.run_dir / "qa" / "snapshot-full.png"
        crop = self.run_dir / "qa" / "snapshot-crop.png"
        full.write_bytes(b"full")
        crop.write_bytes(b"crop")
        visual = self.run_dir / "incoming" / "snapshot-visual.json"
        write_json(visual, {
            "schema": VISUAL_RECEIPT_SCHEMA, "run_id": self.run["run_id"],
            "candidate_id": candidate["candidate_id"], "quote_sha256": candidate["quote_sha256"],
            "full_render_relative": full.relative_to(self.root).as_posix(),
            "full_render_sha256": sha256_file(full),
            "crop_relative": crop.relative_to(self.root).as_posix(),
            "crop_sha256": sha256_file(crop), "reviewer": "qa", "verdict": "PASS",
        })
        ledger_sha = add_visual_receipt(
            isolation_root=self.root, run_dir=self.run_dir, receipt_path=visual,
            expected_ledger_sha=ledger_sha,
        )["ledger_sha256"]
        after_visual = build_views(
            isolation_root=self.root, run_dir=self.run_dir,
            output_dir=self.run_dir / "views" / "after-visual",
        )
        self.assertTrue(after_visual["gates"]["editorial_review_ready"])

        editorial = self.run_dir / "incoming" / "later-editorial-decision.json"
        write_json(editorial, {
            "schema": DECISION_BATCH_SCHEMA, "run_id": self.run["run_id"],
            "decisions": [{
                "candidate_id": candidate["candidate_id"], "decision": "MUST_INCLUDE", "actor": "DAWID",
                "reason": "Dawid podejmuje ostateczną decyzję po przeglądzie.",
                "conflict_acknowledged": False,
            }],
        })
        add_decisions(
            isolation_root=self.root, run_dir=self.run_dir, decision_path=editorial,
            expected_ledger_sha=ledger_sha,
        )
        after_decision = build_views(
            isolation_root=self.root, run_dir=self.run_dir,
            output_dir=self.run_dir / "views" / "after-decision",
        )
        self.assertFalse(after_decision["gates"]["editorial_review_ready"])
        self.assertIn("STALE_SNAPSHOT", after_decision["blockers"]["editorial_review_missing_or_stale"])

    def test_review_receipt_rejects_incomplete_or_forged_artifact(self) -> None:
        ledger_sha, _candidate = self._complete_coverage_with_one_candidate()
        view = self.run_dir / "views" / "forged-review"
        report = build_views(isolation_root=self.root, run_dir=self.run_dir, output_dir=view)
        artifact = view / "editorial-review.md"
        artifact.write_text(
            f"ARTIFACT_SCHEMA: K1_LITE_V2_EDITORIAL_REVIEW_V1\nRUN_ID: {self.run['run_id']}\n"
            f"SNAPSHOT_SHA256: {report['editorial_review']['snapshot_sha256']}\n",
            encoding="utf-8",
        )
        receipt = self.run_dir / "incoming" / "forged-review.json"
        write_json(receipt, {
            "schema": EDITORIAL_REVIEW_RECEIPT_SCHEMA, "run_id": self.run["run_id"],
            "snapshot_sha256": report["editorial_review"]["snapshot_sha256"],
            "review_artifact_relative": artifact.relative_to(self.run_dir).as_posix(),
            "review_artifact_sha256": sha256_file(artifact), "actor": "DAWID", "verdict": "REVIEWED",
            "note": "Dawid przejrzał przedstawione pozycje redakcyjne.",
        })
        with self.assertRaisesRegex(K1LiteV2Error, "ARTIFACT_CONTENT_MISMATCH"):
            add_editorial_review_receipt(
                isolation_root=self.root, run_dir=self.run_dir, receipt_path=receipt,
                expected_ledger_sha=ledger_sha,
            )

    def test_validate_run_rejects_semantic_tamper_for_each_governed_event_type(self) -> None:
        ledger_sha, candidate = self._complete_coverage_with_one_candidate()
        recommendation = self.run_dir / "incoming" / "semantic-key.json"
        write_json(recommendation, {
            "schema": DECISION_BATCH_SCHEMA, "run_id": self.run["run_id"],
            "decisions": [{
                "candidate_id": candidate["candidate_id"], "decision": "KEY_CHATGPT", "actor": "CHATGPT",
                "reason": "Kandydat do testu semantyki ledgera.", "conflict_acknowledged": False,
            }],
        })
        ledger_sha = add_decisions(
            isolation_root=self.root, run_dir=self.run_dir, decision_path=recommendation,
            expected_ledger_sha=ledger_sha,
        )["ledger_sha256"]
        ledger_sha, _report, _artifact = add_current_editorial_review(
            self.root, self.run_dir, self.run, ledger_sha, "semantic-review"
        )
        full = self.run_dir / "qa" / "semantic-full.png"
        crop = self.run_dir / "qa" / "semantic-crop.png"
        full.write_bytes(b"full")
        crop.write_bytes(b"crop")
        visual = self.run_dir / "incoming" / "semantic-visual.json"
        write_json(visual, {
            "schema": VISUAL_RECEIPT_SCHEMA, "run_id": self.run["run_id"],
            "candidate_id": candidate["candidate_id"], "quote_sha256": candidate["quote_sha256"],
            "full_render_relative": full.relative_to(self.root).as_posix(), "full_render_sha256": sha256_file(full),
            "crop_relative": crop.relative_to(self.root).as_posix(), "crop_sha256": sha256_file(crop),
            "reviewer": "qa", "verdict": "PASS",
        })
        add_visual_receipt(
            isolation_root=self.root, run_dir=self.run_dir, receipt_path=visual,
            expected_ledger_sha=ledger_sha,
        )
        ledger_path = self.run_dir / "ledger.jsonl"
        original = read_jsonl(ledger_path)
        cases = [
            ("chunk_result", "chunk_sha256", "0" * 64, "CHUNK_RESULT_RELATION"),
            ("candidate", "quote_sha256", "0" * 64, "CANDIDATE_QUOTE_STATE"),
            ("decision", "conflict_acknowledged", True, "KEY_CHATGPT_CONFLICT_ACK"),
            ("visual_receipt", "source_sha256", "0" * 64, "VISUAL_SOURCE"),
            ("editorial_review_receipt", "actor", "CHATGPT", "EDITORIAL_AUTHORITY"),
        ]
        for event_type, field, value, expected_error in cases:
            with self.subTest(event_type=event_type, field=field):
                tampered = [dict(item) for item in original]
                target = next(item for item in tampered if item.get("event_type") == event_type)
                target[field] = value
                ledger_path.write_text(
                    "".join(json.dumps(item, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n" for item in tampered),
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(K1LiteV2Error, expected_error):
                    validate_run(isolation_root=self.root, run_dir=self.run_dir)
        ledger_path.write_text(
            "".join(json.dumps(item, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n" for item in original),
            encoding="utf-8",
        )

    def test_section_aware_plan_keeps_appendices_as_content(self) -> None:
        sections = json.loads((self.run_dir / "sections.json").read_text(encoding="utf-8"))
        by_name = {item["name"].casefold(): item for item in sections}
        self.assertIn("appendix 3", by_name)
        self.assertIn("appendix 4", by_name)
        self.assertEqual(by_name["appendix 4"]["role"], "CONTENT")
        self.assertEqual(by_name["bibliography"]["role"], "REFERENCE")
        self.assertEqual(by_name["bibliography"]["page_from"], "P0006")

    def test_every_page_is_covered_once_including_reference_pages(self) -> None:
        covered = [page for chunk in self.chunks for page in chunk["pages"]]
        self.assertEqual(covered, [f"P{number:04d}" for number in range(1, 8)])
        self.assertTrue(any(chunk["role"] == "REFERENCE" for chunk in self.chunks))

    def test_worker_packets_have_only_sparse_probe_markers(self) -> None:
        for chunk in self.chunks:
            packet = (self.run_dir / "worker-input" / f"{chunk['chunk_id']}.md").read_text(encoding="utf-8")
            self.assertEqual(packet.count("[[PROBE:"), len(chunk["probes"]))
            self.assertNotIn("/L1 ", packet)

    def test_partial_line_quote_is_exact_page_not_tolerance(self) -> None:
        document = read_source(self.source, sha256_file(self.pdf))
        result = find_quote(document.pages[0], "comet impact happened in 7640 bc")
        self.assertEqual(result["match_scope"], "DECLARED_PAGE_EXACT")
        self.assertEqual(result["boundary"], "PARTIAL_LINE")

    def test_quote_on_wrong_page_fails(self) -> None:
        document = read_source(self.source, sha256_file(self.pdf))
        with self.assertRaisesRegex(K1LiteV2Error, "QUOTE_NOT_FOUND"):
            find_quote(document.pages[1], "The comet impact happened in 7640 bc")

    def test_numeric_candidate_requires_fact_key(self) -> None:
        chunk = self.chunks[0]
        result = make_result(
            self.run,
            chunk,
            candidates=[
                {
                    "local_id": "A",
                    "claim": "Pierwsza data impaktu",
                    "page": "P0001",
                    "quote": "The comet impact happened in 7640 bc near the northern coast.",
                    "category": "OPEN_DISCOVERY",
                    "k0_target": "OUTSIDE_K0",
                    "film_value": 3,
                    "risk": 2,
                    "speaker_mode": "AUTHOR_CLAIM",
                    "genealogy": "source",
                    "facts": [],
                }
            ],
        )
        incoming = self.run_dir / "incoming" / "bad.json"
        write_json(incoming, result)
        with self.assertRaisesRegex(K1LiteV2Error, "NUMERIC_QUOTE_FACTS_REQUIRED"):
            import_worker_result(
                isolation_root=self.root,
                run_dir=self.run_dir,
                result_path=incoming,
                expected_ledger_sha="CREATE_NEW",
            )

    def test_full_flow_retains_candidates_detects_conflict_and_builds_views(self) -> None:
        ledger_sha = "CREATE_NEW"
        candidate_chunk = next(chunk for chunk in self.chunks if "P0001" in chunk["pages"] and "P0002" in chunk["pages"])
        candidates = [
            {
                "local_id": "A",
                "claim": "Autorzy podają pierwszą datę impaktu",
                "page": "P0001",
                "quote": "The comet impact happened in 7640 bc near the northern coast.",
                "category": "OPEN_DISCOVERY",
                "k0_target": "Q-TEST",
                "film_value": 3,
                "risk": 2,
                "speaker_mode": "AUTHOR_CLAIM",
                "genealogy": "same source",
                "facts": [{"key": "comet_impact_date", "value": "7640 bc", "subject_terms": ["comet", "impact"]}],
            },
            {
                "local_id": "B",
                "claim": "Podsumowanie podaje inną datę impaktu",
                "page": "P0002",
                "quote": "A later summary calls the same comet impact 7620 bc near the northern coast.",
                "category": "OPEN_DISCOVERY",
                "k0_target": "Q-TEST",
                "film_value": 3,
                "risk": 3,
                "speaker_mode": "AUTHOR_CLAIM",
                "genealogy": "same source",
                "facts": [{"key": "comet_impact_date", "value": "7620 bc", "subject_terms": ["comet", "impact"]}],
            },
        ]
        result_file = self.run_dir / "incoming" / "candidate.json"
        write_json(result_file, make_result(self.run, candidate_chunk, candidates=candidates))
        imported = import_worker_result(
            isolation_root=self.root,
            run_dir=self.run_dir,
            result_path=result_file,
            expected_ledger_sha=ledger_sha,
        )
        ledger_sha = imported["ledger_sha256"]

        for chunk in self.chunks:
            if chunk["chunk_id"] == candidate_chunk["chunk_id"]:
                continue
            result_file = self.run_dir / "incoming" / f"{chunk['chunk_id']}.json"
            write_json(result_file, make_result(self.run, chunk, candidates=[]))
            imported = import_worker_result(
                isolation_root=self.root,
                run_dir=self.run_dir,
                result_path=result_file,
                expected_ledger_sha=ledger_sha,
            )
            ledger_sha = imported["ledger_sha256"]

        ledger = read_jsonl(self.run_dir / "ledger.jsonl")
        candidate_records = [item for item in ledger if item.get("event_type") == "candidate"]
        self.assertEqual(len(candidate_records), 2)
        self.assertEqual({item["boundary"] for item in candidate_records}, {"FULL_LINES"})

        decision_file = self.run_dir / "incoming" / "decisions.json"
        write_json(
            decision_file,
            {
                "schema": DECISION_BATCH_SCHEMA,
                "run_id": self.run["run_id"],
                "decisions": [
                    {
                        "candidate_id": item["candidate_id"],
                        "decision": "MUST_INCLUDE",
                        "actor": "DAWID",
                        "reason": "Test konfliktu",
                        "conflict_acknowledged": True,
                    }
                    for item in candidate_records
                ],
            },
        )
        ledger_sha = add_decisions(
            isolation_root=self.root,
            run_dir=self.run_dir,
            decision_path=decision_file,
            expected_ledger_sha=ledger_sha,
        )["ledger_sha256"]

        full_artifacts: list[Path] = []
        for item in candidate_records:
            full = self.root / "QA" / f"{item['candidate_id']}-full.png"
            crop = self.root / "QA" / f"{item['candidate_id']}-crop.png"
            full.parent.mkdir(parents=True, exist_ok=True)
            full.write_bytes(b"full-render-" + item["candidate_id"].encode())
            crop.write_bytes(b"crop-" + item["candidate_id"].encode())
            full_artifacts.append(full)
            receipt_file = self.run_dir / "incoming" / f"{item['candidate_id']}-visual.json"
            write_json(
                receipt_file,
                {
                    "schema": VISUAL_RECEIPT_SCHEMA,
                    "run_id": self.run["run_id"],
                    "candidate_id": item["candidate_id"],
                    "quote_sha256": item["quote_sha256"],
                    "full_render_relative": full.relative_to(self.root).as_posix(),
                    "full_render_sha256": sha256_file(full),
                    "crop_relative": crop.relative_to(self.root).as_posix(),
                    "crop_sha256": sha256_file(crop),
                    "reviewer": "quality-controller",
                    "verdict": "PASS",
                },
            )
            ledger_sha = add_visual_receipt(
                isolation_root=self.root,
                run_dir=self.run_dir,
                receipt_path=receipt_file,
                expected_ledger_sha=ledger_sha,
            )["ledger_sha256"]

        output = self.run_dir / "views" / "build-001"
        report = build_views(isolation_root=self.root, run_dir=self.run_dir, output_dir=output)
        self.assertFalse(report["gates"]["editorial_review_ready"])
        self.assertEqual(report["blockers"]["editorial_review_missing_or_stale"], ["MISSING"])
        review_text = (output / "editorial-review.md").read_text(encoding="utf-8")
        self.assertIn(f"RUN_ID: {self.run['run_id']}", review_text)
        self.assertIn("FILM_VALUE: 3", review_text)
        self.assertIn("RISK: 3", review_text)
        self.assertIn("CONFLICT: TAK", review_text)
        ledger_sha, _pre_review, _artifact = add_current_editorial_review(
            self.root, self.run_dir, self.run, ledger_sha, "review-accepted"
        )
        output = self.run_dir / "views" / "build-002"
        report = build_views(isolation_root=self.root, run_dir=self.run_dir, output_dir=output)
        self.assertTrue(report["gates"]["coverage_ready"])
        self.assertTrue(report["gates"]["selected_visual_ready"])
        self.assertTrue(report["gates"]["selected_conflicts_acknowledged"])
        self.assertTrue(report["gates"]["editorial_review_ready"])
        self.assertGreaterEqual(report["counts"]["conflicts"], 1)
        directories_before_validation = {
            path.relative_to(self.run_dir).as_posix()
            for path in self.run_dir.rglob("*")
            if path.is_dir()
        }
        fresh_validation = validate_run(isolation_root=self.root, run_dir=self.run_dir)
        directories_after_validation = {
            path.relative_to(self.run_dir).as_posix()
            for path in self.run_dir.rglob("*")
            if path.is_dir()
        }
        self.assertTrue(fresh_validation["gate_ready"])
        self.assertTrue(fresh_validation["compile_ready"])
        self.assertEqual(fresh_validation["gates"], report["gates"])
        self.assertEqual(directories_after_validation, directories_before_validation)
        self.assertEqual(report["metrics"]["calls"], len(self.chunks))
        self.assertEqual(report["blockers"]["quote_verification_failed"], [])
        self.assertTrue((output / "quote-verification.json").is_file())
        batch = verify_quote_batch(
            isolation_root=self.root,
            run_dir=self.run_dir,
            output_path=self.run_dir / "qa" / "quotes-001.json",
        )
        self.assertEqual(batch["failed"], 0)
        staging = (output / "staging-preview.md").read_text(encoding="utf-8")
        self.assertIn("REVIEWED_PREVIEW_REQUIRES_COMPILER", staging)
        self.assertIn("CONFLICT: `YES`", staging)

        # The review remains current after a purely visual change, but altered
        # evidence images must independently fail the visual integrity gate.
        full_artifacts[0].write_bytes(b"tampered-full-render")
        tampered = build_views(
            isolation_root=self.root,
            run_dir=self.run_dir,
            output_dir=self.run_dir / "views" / "build-003-tampered-visual",
        )
        self.assertFalse(tampered["gates"]["selected_visual_ready"])
        self.assertTrue(tampered["gates"]["editorial_review_ready"])
        self.assertIn(candidate_records[0]["candidate_id"], tampered["blockers"]["visual_integrity_failures"])
        tampered_validation = validate_run(isolation_root=self.root, run_dir=self.run_dir)
        self.assertFalse(tampered_validation["gate_ready"])
        self.assertFalse(tampered_validation["compile_ready"])
        self.assertFalse(tampered_validation["gates"]["selected_visual_ready"])

    def test_layout_inspection_is_hash_bound_and_create_new(self) -> None:
        output = self.run_dir / "qa" / "layout-001.json"
        report = inspect_pdf_layout(isolation_root=self.root, run_dir=self.run_dir, output_path=output)
        self.assertEqual(report["pdf_sha256"], self.run["pdf_sha256"])
        self.assertEqual(report["physical_pages"], len(self.bodies))
        self.assertTrue(output.is_file())
        with self.assertRaisesRegex(K1LiteV2Error, "OUTPUT_FILE_EXISTS"):
            inspect_pdf_layout(isolation_root=self.root, run_dir=self.run_dir, output_path=output)

    def test_pdf_visual_policy_cannot_be_downgraded_in_run_json(self) -> None:
        run_path = self.run_dir / "run.json"
        payload = json.loads(run_path.read_text(encoding="utf-8"))
        payload["logical_source_kind"] = "STANDALONE_TEXT"
        payload["visual_policy"] = "NOT_APPLICABLE"
        write_json(run_path, payload)
        with self.assertRaisesRegex(K1LiteV2Error, "RUN_LOGICAL_SOURCE_KIND_STALE"):
            validate_run(isolation_root=self.root, run_dir=self.run_dir)

    def test_engine_version_missing_or_old_is_rejected(self) -> None:
        run_path = self.run_dir / "run.json"
        payload = json.loads(run_path.read_text(encoding="utf-8"))
        payload.pop("engine_version")
        write_json(run_path, payload)
        with self.assertRaisesRegex(K1LiteV2Error, "RUN_ENGINE_VERSION_UNSUPPORTED"):
            validate_run(isolation_root=self.root, run_dir=self.run_dir)

    def test_k0_brief_keeps_scope_without_copying_whole_document(self) -> None:
        source = (
            "ROBOCZY_TYTUŁ_CZĘŚCI: Strażnicy, którzy zepsuli świat\n"
            "TEMAT W JEDNYM ZDANIU: rekonstrukcja źródłowa\n"
            "PYTANIE GŁÓWNE: co zrobili Strażnicy?\n"
            "WĄTKI OBOWIĄZKOWE: Nephilim i potop\n"
            "WĄTKI DO POMINIĘCIA W CZĘŚCI I: maszyna Uriela\n"
            "TRYB RESEARCHU: SOURCES_ONLY\n"
            "POLITYKA WERYFIKACJI: SOURCE_FIRST_K4\n"
            "NIEPOŻĄDANA SEKCJA: nie kopiuj tego\n"
        )
        brief = make_analysis_brief(source)
        self.assertIn("Nephilim i potop", brief)
        self.assertIn("maszyna Uriela", brief)
        self.assertNotIn("NIEPOŻĄDANA", brief)

    def test_conflict_scan_distinguishes_dates_durations_and_other_declared_facts(self) -> None:
        first_body = (
            "Civilization at the site flourished between 7000 and 6000 bc after the 7640 bc "
            "cometary impact and rebuilt 4,000 years later."
        )
        first_page = Page(
            1,
            first_body,
            (first_body,),
            sha256_bytes((first_body + "\n").encode("utf-8")),
            "NATIVE",
            "NONE",
        )
        candidate = {
            "facts": [
                {
                    "key": "authors_comet_impact_date",
                    "value": "7640 bc",
                    "subject_terms": ["cometary impact", "civilization"],
                },
                {
                    "key": "site_period",
                    "value": "7000 and 6000 bc",
                    "subject_terms": ["site", "flourished"],
                },
            ]
        }
        document = SourceDocument(Path("synthetic"), "A" * 64, "B" * 64, "TEST", (first_page,))
        self.assertEqual(find_conflicts(document, {"CANDIDATE": candidate})["conflict_count"], 0)

        second_body = "A competing civilization account dates the cometary impact to 7620 bc."
        second_page = Page(
            2,
            second_body,
            (second_body,),
            sha256_bytes((second_body + "\n").encode("utf-8")),
            "NATIVE",
            "NONE",
        )
        conflicting = SourceDocument(
            Path("synthetic"), "A" * 64, "B" * 64, "TEST", (first_page, second_page)
        )
        self.assertGreaterEqual(find_conflicts(conflicting, {"CANDIDATE": candidate})["conflict_count"], 1)

    def test_conflict_scan_ignores_unrelated_year_for_non_numeric_fact(self) -> None:
        body = (
            "Late one night in October 1965 the object appeared. The witnesses had "
            "flulike symptoms for several days."
        )
        page = Page(
            1,
            body,
            (body,),
            sha256_bytes((body + "\n").encode("utf-8")),
            "NATIVE",
            "NONE",
        )
        candidate = {
            "facts": [
                {
                    "key": "symptoms_duration",
                    "value": "several days",
                    "subject_terms": ["symptoms", "days"],
                }
            ]
        }
        document = SourceDocument(Path("synthetic"), "A" * 64, "B" * 64, "TEST", (page,))
        self.assertEqual(find_conflicts(document, {"CANDIDATE": candidate})["conflict_count"], 0)

    def test_more_than_two_candidates_is_rejected_without_ledger(self) -> None:
        chunk = self.chunks[0]
        template = {
            "local_id": "A",
            "claim": "Długi prawidłowy opis kandydata",
            "page": chunk["pages"][0],
            "quote": "The comet impact happened in 7640 bc near the northern coast.",
            "category": "OPEN_DISCOVERY",
            "k0_target": "Q",
            "film_value": 1,
            "risk": 1,
            "speaker_mode": "AUTHOR_CLAIM",
            "genealogy": "source",
            "facts": [{"key": "comet_impact_date", "value": "7640 bc", "subject_terms": ["comet", "impact"]}],
        }
        candidates = []
        for local_id in ("A", "B", "C"):
            item = dict(template)
            item["local_id"] = local_id
            candidates.append(item)
        result_file = self.run_dir / "incoming" / "overflow-bad.json"
        write_json(result_file, make_result(self.run, chunk, candidates=candidates))
        with self.assertRaisesRegex(K1LiteV2Error, "CANDIDATE_PAGE_LIMIT_EXCEEDED"):
            import_worker_result(
                isolation_root=self.root,
                run_dir=self.run_dir,
                result_path=result_file,
                expected_ledger_sha="CREATE_NEW",
            )
        self.assertFalse((self.run_dir / "ledger.jsonl").exists())

    def test_bad_probe_is_rejected(self) -> None:
        chunk = self.chunks[0]
        result = make_result(self.run, chunk, candidates=[])
        result["probe_answers"][chunk["probes"][0]["probe_id"]] = "wrong answer"
        result_file = self.run_dir / "incoming" / "probe-bad.json"
        write_json(result_file, result)
        with self.assertRaisesRegex(K1LiteV2Error, "PROBE_MISMATCH"):
            import_worker_result(
                isolation_root=self.root,
                run_dir=self.run_dir,
                result_path=result_file,
                expected_ledger_sha="CREATE_NEW",
            )

    def test_ledger_compare_and_swap_blocks_wrong_hash(self) -> None:
        chunk = self.chunks[0]
        result_file = self.run_dir / "incoming" / "first.json"
        write_json(result_file, make_result(self.run, chunk, candidates=[]))
        import_worker_result(
            isolation_root=self.root,
            run_dir=self.run_dir,
            result_path=result_file,
            expected_ledger_sha="CREATE_NEW",
        )
        other_chunk = self.chunks[1]
        other_file = self.run_dir / "incoming" / "second.json"
        write_json(other_file, make_result(self.run, other_chunk, candidates=[]))
        with self.assertRaisesRegex(K1LiteV2Error, "LEDGER_SHA_MISMATCH"):
            import_worker_result(
                isolation_root=self.root,
                run_dir=self.run_dir,
                result_path=other_file,
                expected_ledger_sha="0" * 64,
            )

    def test_run_creation_refuses_existing_target(self) -> None:
        with self.assertRaisesRegex(K1LiteV2Error, "RUN_DIRECTORY_EXISTS"):
            initialize_run(
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

    def test_source_outside_isolation_is_blocked(self) -> None:
        with tempfile.TemporaryDirectory(prefix="outside-v2-") as other:
            outside = Path(other) / "outside.md"
            outside.write_text("outside", encoding="utf-8")
            with self.assertRaisesRegex(K1LiteV2Error, "PATH_OUTSIDE_ISOLATION_ROOT"):
                initialize_run(
                    isolation_root=self.root,
                    source_path=outside,
                    expected_source_sha=sha256_file(outside),
                    pdf_path=self.pdf,
                    expected_pdf_sha=sha256_file(self.pdf),
                    run_dir=self.root / "_work" / "K1" / "k1-lite-v2" / "outside",
                    k0_path=None,
                    expected_k0_sha=None,
                    target_min=1000,
                    target_max=4000,
                )

    def test_legacy_text_twin_can_be_reused(self) -> None:
        legacy = self.root / "PROJECT" / "sources" / "book-legacy.md"
        parts = [
            "# Source transcript: test",
            "",
            f"- SOURCE_PDF_SHA256: `{sha256_file(self.pdf)}`",
            "",
            "---",
            "",
        ]
        for number, body in enumerate(self.bodies, start=1):
            parts.extend([f'<a id="pdf-page-{number:04d}"></a>', "", f"## PDF page {number}", "", body, ""])
        legacy.write_text("\n".join(parts), encoding="utf-8")
        report = compare_text_twins(
            isolation_root=self.root,
            first_path=legacy,
            first_sha=sha256_file(legacy),
            second_path=self.source,
            second_sha=sha256_file(self.source),
            pdf_sha=sha256_file(self.pdf),
        )
        self.assertTrue(report["equivalent"])
        self.assertEqual(report["recommendation"], "REUSE_EXISTING_TEXT")

    def test_standalone_md_and_txt_create_runs_without_pdf_and_use_global_lines(self) -> None:
        for extension, encoding in ((".md", "utf-8"), (".txt", "utf-8-sig")):
            with self.subTest(extension=extension):
                source = self.root / "PROJECT" / "sources" / f"standalone{extension}"
                source.write_text(
                    "Nagłówek\n\nNajmocniejszy wątek źródłowy jest zapisany dokładnie tutaj.\nDalszy kontekst.\n",
                    encoding=encoding,
                )
                run_dir = self.root / "_work" / "K1" / "k1-lite-v2" / f"run-{extension[1:]}"
                run = initialize_run(
                    isolation_root=self.root,
                    source_path=source,
                    expected_source_sha=sha256_file(source),
                    pdf_path=None,
                    expected_pdf_sha=None,
                    run_dir=run_dir,
                    k0_path=None,
                    expected_k0_sha=None,
                    target_min=1000,
                    target_max=4000,
                )
                document = read_source(source)
                resolved = find_quote(document.pages[0], "Najmocniejszy wątek źródłowy jest zapisany dokładnie tutaj.")
                self.assertEqual(resolved["locator"], "L3-L3")
                self.assertEqual(resolved["match_scope"], "DECLARED_LINE_RANGE_EXACT")
                self.assertIsNone(run["pdf_relative"])
                self.assertEqual(run["pdf_sha256"], "NONE")
                self.assertEqual(run["logical_source_kind"], "STANDALONE_TEXT")
                self.assertEqual(run["source_coverage"], "L1-L4")
                self.assertEqual(run["engine_version"], "2.1.0")
                self.assertEqual(validate_run(isolation_root=self.root, run_dir=run_dir)["verdict"], "PASS")

    def test_srt_and_vtt_use_exact_machine_verifiable_timestamp_ranges(self) -> None:
        cases = {
            ".srt": (
                "1\n00:00:01,000 --> 00:00:04,250\nPierwszy kontrowersyjny fragment źródła.\n\n"
                "2\n00:00:05,000 --> 00:00:08,500\nDrugi fragment daje potrzebny kontekst.\n",
                "Pierwszy kontrowersyjny fragment źródła.",
                "[00:00:01.000-00:00:04.250]",
            ),
            ".vtt": (
                "WEBVTT\n\ncue-one\n00:00:10.000 --> 00:00:14.750 align:start\n"
                "Weryfikowalny fragment napisów znajduje się tutaj.\n",
                "Weryfikowalny fragment napisów znajduje się tutaj.",
                "[00:00:10.000-00:00:14.750]",
            ),
        }
        for extension, (payload, quote, expected_locator) in cases.items():
            with self.subTest(extension=extension):
                source = self.root / "PROJECT" / "sources" / f"captions{extension}"
                source.write_text(payload, encoding="utf-8")
                run_dir = self.root / "_work" / "K1" / "k1-lite-v2" / f"run-captions-{extension[1:]}"
                run = initialize_run(
                    isolation_root=self.root,
                    source_path=source,
                    expected_source_sha=sha256_file(source),
                    pdf_path=None,
                    expected_pdf_sha=None,
                    run_dir=run_dir,
                    k0_path=None,
                    expected_k0_sha=None,
                    target_min=1000,
                    target_max=4000,
                )
                document = read_source(source)
                resolved = find_quote(document.pages[0], quote)
                self.assertEqual(resolved["locator"], expected_locator)
                self.assertEqual(resolved["match_scope"], "DECLARED_TIMESTAMP_EXACT")
                self.assertEqual(run["logical_source_kind"], "STANDALONE_TIMED")
                self.assertEqual(run["locator_kind"], "TIMESTAMP")

    def test_pdf_arguments_and_source_kinds_fail_closed(self) -> None:
        standalone = self.root / "PROJECT" / "sources" / "plain.md"
        standalone.write_text("Samodzielny tekst źródłowy o wystarczającej długości.\n", encoding="utf-8")
        with self.assertRaisesRegex(K1LiteV2Error, "PDF_REQUIRED_FOR_PDF_TRANSCRIPT"):
            read_source(self.source)
        with self.assertRaisesRegex(K1LiteV2Error, "BACKING_PDF_NOT_ALLOWED"):
            read_source(standalone, sha256_file(self.pdf))
        orphan_sidecar = self.root / "PROJECT" / "sources" / "orphan--TEXT.md"
        orphan_sidecar.write_text("To nie jest poprawny transcript PDF.\n", encoding="utf-8")
        with self.assertRaisesRegex(K1LiteV2Error, "PDF_TRANSCRIPT_METADATA_INVALID"):
            read_source(orphan_sidecar)
        wrong_name = self.root / "PROJECT" / "sources" / "wrong--TEXT.md"
        wrong_name.write_text(self.source.read_text(encoding="utf-8"), encoding="utf-8")
        with self.assertRaisesRegex(K1LiteV2Error, "SOURCE_PDF_SIDECAR_NAME_MISMATCH"):
            read_source(
                wrong_name,
                sha256_file(self.pdf),
                expected_pdf_path=self.pdf,
                isolation_root=self.root,
            )
        other_pdf = self.root / "PROJECT" / "sources" / "other.pdf"
        other_pdf.write_bytes(self.pdf.read_bytes())
        wrong_pair = self.root / "PROJECT" / "sources" / "other--TEXT.md"
        wrong_pair.write_text(
            self.source.read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(K1LiteV2Error, "SOURCE_PDF_PATH_MISMATCH"):
            read_source(
                wrong_pair,
                sha256_file(self.pdf),
                expected_pdf_path=other_pdf,
                isolation_root=self.root,
            )
        with self.assertRaisesRegex(K1LiteV2Error, "PDF_ARGUMENT_PAIR_REQUIRED"):
            initialize_run(
                isolation_root=self.root,
                source_path=standalone,
                expected_source_sha=sha256_file(standalone),
                pdf_path=self.pdf,
                expected_pdf_sha=None,
                run_dir=self.root / "_work" / "K1" / "k1-lite-v2" / "run-half-pdf",
                k0_path=None,
                expected_k0_sha=None,
                target_min=1000,
                target_max=4000,
            )

    def test_malformed_subtitles_are_rejected(self) -> None:
        malformed = self.root / "PROJECT" / "sources" / "bad.srt"
        malformed.write_text("1\n00:00:05,000 --> 00:00:04,000\nOdwrócony zakres czasu.\n", encoding="utf-8")
        with self.assertRaisesRegex(K1LiteV2Error, "SUBTITLE_CUE_RANGE_INVALID"):
            read_source(malformed)

    def test_standalone_visual_is_not_applicable_and_does_not_block_selected_card(self) -> None:
        source = self.root / "PROJECT" / "sources" / "native.txt"
        quote = "Ten dosłowny fragment źródła powinien wejść do bazy dowodów."
        source.write_text(f"Wprowadzenie.\n{quote}\nKontekst końcowy.\n", encoding="utf-8")
        run_dir = self.root / "_work" / "K1" / "k1-lite-v2" / "run-native-visual"
        run = initialize_run(
            isolation_root=self.root,
            source_path=source,
            expected_source_sha=sha256_file(source),
            pdf_path=None,
            expected_pdf_sha=None,
            run_dir=run_dir,
            k0_path=None,
            expected_k0_sha=None,
            target_min=1000,
            target_max=4000,
        )
        chunk = read_jsonl(run_dir / "chunks.jsonl")[0]
        result_file = run_dir / "incoming" / "result.json"
        write_json(
            result_file,
            make_result(
                run,
                chunk,
                candidates=[{
                    "local_id": "A", "claim": "Wątek wybrany do bazy dowodów", "page": "P0001",
                    "quote": quote, "category": "OPEN_DISCOVERY", "k0_target": "OUTSIDE_K0",
                    "film_value": 3, "risk": 1, "speaker_mode": "FACT_IN_SOURCE",
                    "genealogy": "source", "facts": [],
                }],
            ),
        )
        ledger_sha = import_worker_result(
            isolation_root=self.root, run_dir=run_dir, result_path=result_file, expected_ledger_sha="CREATE_NEW"
        )["ledger_sha256"]
        candidate = next(item for item in read_jsonl(run_dir / "ledger.jsonl") if item.get("event_type") == "candidate")
        decisions = run_dir / "incoming" / "decisions.json"
        write_json(decisions, {
            "schema": DECISION_BATCH_SCHEMA,
            "run_id": run["run_id"],
            "decisions": [{
                "candidate_id": candidate["candidate_id"], "decision": "MUST_INCLUDE", "actor": "DAWID",
                "reason": "Wybrany do testu źródła tekstowego", "conflict_acknowledged": False,
            }],
        })
        ledger_sha = add_decisions(
            isolation_root=self.root, run_dir=run_dir, decision_path=decisions, expected_ledger_sha=ledger_sha
        )["ledger_sha256"]
        report = build_views(isolation_root=self.root, run_dir=run_dir, output_dir=run_dir / "views" / "native")
        self.assertTrue(report["gates"]["selected_visual_ready"])
        self.assertEqual(report["blockers"]["visual_missing_or_stale"], [])
        self.assertIn("VISUAL: `NOT_APPLICABLE`", (run_dir / "views" / "native" / "staging-preview.md").read_text(encoding="utf-8"))
        layout = inspect_pdf_layout(
            isolation_root=self.root, run_dir=run_dir, output_path=run_dir / "qa" / "layout-native.json"
        )
        self.assertFalse(layout["applicable"])
        fake_receipt = run_dir / "incoming" / "visual.json"
        write_json(fake_receipt, {})
        with self.assertRaisesRegex(K1LiteV2Error, "VISUAL_NOT_APPLICABLE"):
            add_visual_receipt(
                isolation_root=self.root, run_dir=run_dir, receipt_path=fake_receipt, expected_ledger_sha=ledger_sha
            )

    def test_standalone_source_change_invalidates_run(self) -> None:
        source = self.root / "PROJECT" / "sources" / "stale.txt"
        source.write_text("Pierwotny materiał źródłowy pozostaje stabilny.\n", encoding="utf-8")
        run_dir = self.root / "_work" / "K1" / "k1-lite-v2" / "run-stale-text"
        initialize_run(
            isolation_root=self.root, source_path=source, expected_source_sha=sha256_file(source),
            pdf_path=None, expected_pdf_sha=None, run_dir=run_dir, k0_path=None, expected_k0_sha=None,
            target_min=1000, target_max=4000,
        )
        source.write_text("Zmieniony materiał źródłowy unieważnia run.\n", encoding="utf-8")
        with self.assertRaisesRegex(K1LiteV2Error, "RUN_SOURCE_STALE"):
            validate_run(isolation_root=self.root, run_dir=run_dir)


if __name__ == "__main__":
    unittest.main(verbosity=2)
