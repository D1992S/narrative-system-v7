"""K1 monitoring: pure projections, no import/prepare/recover or PDF conversion."""
import hashlib
import json
import re
from pathlib import Path
from panel_read import ReadError, k1_core, safe_relative

GATES = {"coverage_ready", "quotes_ready", "decisions_current", "selected_visual_ready",
         "selected_conflicts_acknowledged", "editorial_review_ready"}
RAW = re.compile(r"^a\d{6}-[A-F0-9]{64}\.json$")

def read_run(run_dir, root, store):
    core = k1_core()
    run = store.read(run_dir / "run.json", "json")
    if not run or run.get("schema") != core.RUN_SCHEMA:
        raise ReadError("Nieprawidłowy run.json: " + run_dir.name)
    chunks = store.read(run_dir / "chunks.jsonl", "jsonl")
    ledger = store.read(run_dir / "ledger.jsonl", "jsonl")
    coverage = core.coverage_state(chunks, ledger)
    candidates = core.active_candidates(ledger)
    decisions = core.latest_editorial_decisions(ledger)
    recommendations = core.latest_recommendations(ledger)
    selected = core.selected_candidates(candidates, decisions, recommendations)
    stale = set(core.stale_active_state(candidates, decisions) + core.stale_active_state(candidates, recommendations))
    valid_visual = set()
    for cid, receipt in core.latest_visuals(ledger).items():
        candidate = candidates.get(cid, {})
        if (cid in selected and receipt.get("verdict") == "PASS"
            and receipt.get("quote_sha256") == candidate.get("quote_sha256")
            and receipt.get("source_sha256") == run.get("source_sha256")
            and all(store.bound(receipt.get(field), receipt.get(digest)) for field, digest in
                (("full_render_relative", "full_render_sha256"), ("crop_relative", "crop_sha256")))):
            valid_visual.add(cid)
    source_current = store.bound(run.get("source_relative"), run.get("source_sha256"))
    if run.get("pdf_relative"):
        source_current = source_current and store.bound(run["pdf_relative"], run.get("pdf_sha256"))
    if run.get("k0_relative"):
        source_current = source_current and store.bound(run["k0_relative"], run.get("k0_sha256"))
    review = core.latest_editorial_review_receipt(ledger)
    reviewed = False
    if review:
        rel = review.get("review_artifact_relative")
        try:
            artifact = safe_relative(root, str((run_dir / rel).relative_to(root))) if rel else None
            reviewed = (review.get("actor") == "DAWID" and review.get("verdict") == "REVIEWED"
                and review.get("snapshot_sha256") == core.editorial_snapshot_sha256(run, chunks, ledger)
                and artifact is not None and store.digest(artifact) == review.get("review_artifact_sha256"))
        except (ReadError, ValueError, TypeError):
            reviewed = False
    tasks = []
    jobs = run_dir / "jobs"
    if jobs.exists():
        for folder in sorted(jobs.iterdir()):
            if not folder.is_dir() or folder.is_symlink():
                continue
            request = store.read(folder / "request.json", "json")
            if request is None:
                continue
            ident = hashlib.sha256((json.dumps(request, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()).hexdigest().upper()
            if request.get("schema") != "K1_WORK_TASK_V1" or folder.name != ident:
                tasks.append({"id": folder.name, "status": "INVALID", "detail": "Nieprawidłowa tożsamość zadania"})
                continue
            chunk = next((c for c in chunks if c.get("chunk_id") == request.get("chunk_id")), {})
            if (not source_current or request.get("analysis_key") != run.get("analysis_key")
                or request.get("run_id") != run.get("run_id")
                or request.get("packet_sha256") != chunk.get("packet_sha256")
                or request.get("chunk_sha256") != chunk.get("chunk_sha256")):
                continue  # Superseded analysis is not current work.
            receipts = [e for e in ledger if e.get("event_type") == "result_receipt"
                and e.get("chunk_id") == request.get("chunk_id") and e.get("continuation_no") == request.get("continuation_no")]
            if receipts:
                rec = receipts[-1]
                if not store.bound(rec.get("stored_relative"), rec.get("result_sha256")):
                    tasks.append({"id": folder.name, "status": "INVALID", "detail": "Uszkodzony ślad importu; kontrola lokalna"})
                else:
                    accepted = store.read(folder / "accepted.json", "json")
                    if not accepted or accepted.get("task_id") != ident or accepted.get("result_sha256") != rec.get("result_sha256"):
                        tasks.append({"id": folder.name, "status": "CONFIRMATION_PENDING",
                                      "detail": "Zaimportowano; potwierdzenie lokalne, bez ponawiania odpowiedzi modelu"})
                continue
            completed = [e for e in ledger if e.get("event_type") == "chunk_result" and e.get("chunk_id") == request.get("chunk_id")]
            if len(completed) > request.get("continuation_no", -1):
                continue
            raws = sorted(p for p in folder.iterdir() if RAW.fullmatch(p.name))
            status, detail = "WAITING_FOR_RESPONSE", "Czeka na odpowiedź"
            if raws:
                raw = raws[-1]
                if store.digest(raw) != raw.stem.split("-")[1]:
                    status, detail = "INVALID", "Uszkodzona zapisana odpowiedź; kontrola lokalna"
                else:
                    errors = list(folder.glob(raw.stem + ".error-*.json"))
                    canonical = folder / (raw.stem + ".canonical.json")
                    if errors:
                        status, detail = "NEEDS_CORRECTION", "Odpowiedź wymaga poprawy; zachowana na dysku"
                    elif canonical.exists():
                        status, detail = "RETRY_LOCAL", "Wynik przygotowany; dokończyć import lokalnie"
                    else:
                        status, detail = "SAVED_RESPONSE", "Odpowiedź zapisana; sprawdzić/importować lokalnie"
            tasks.append({"id": folder.name, "status": status, "detail": detail})
    reports = []
    views = run_dir / "views"
    if views.exists():
        for path in views.glob("*/compile-report.json"):
            report = store.read(path, "json")
            valid = (report and report.get("schema") == core.COMPILE_REPORT_SCHEMA
                and report.get("run_id") == run.get("run_id")
                and set(report.get("gates", {})) == GATES
                and all(type(v) is bool for v in report["gates"].values())
                and report.get("ledger_sha256") == store.digest(run_dir / "ledger.jsonl")
                and report.get("source_sha256") == run.get("source_sha256")
                and report.get("pdf_sha256") == run.get("pdf_sha256")
                and source_current)
            reports.append((valid, path.stat().st_mtime, report))
    current_reports = [r for r in reports if r[0]]
    # Same snapshot with conflicting reports is uncertain, never pick a green result by mtime.
    agree = len({json.dumps(r[2]["gates"], sort_keys=True) for r in current_reports}) <= 1
    report = max(current_reports, key=lambda r:r[1])[2] if current_reports and agree else {}
    gates = report.get("gates", {})
    if stale or not reviewed or (run.get("visual_policy") == "REQUIRED" and set(selected) - valid_visual):
        gates = dict(gates)
        if stale and gates: gates["decisions_current"] = False
        if not reviewed and gates: gates["editorial_review_ready"] = False
        if set(selected) - valid_visual and run.get("visual_policy") == "REQUIRED" and gates: gates["selected_visual_ready"] = False
    return {
        "name": Path(run.get("source_relative", "")).name, "run": run_dir.name, "run_id": run["run_id"],
        "source_relative": run.get("source_relative"), "pdf_relative": run.get("pdf_relative"),
        "source_current": source_current, "analysis_key": run.get("analysis_key"),
        "chunks_total": len(chunks), "chunks_done": sum(c["complete"] for c in coverage),
        "waiting": [t["id"] for t in tasks], "tasks": tasks,
        "candidates": len(candidates), "recommendations": len(set(recommendations) & set(candidates) - stale),
        "decided": len(set(decisions) & set(candidates) - stale), "selected": len(selected),
        "visual_required": run.get("visual_policy") == "REQUIRED",
        "visual": len(valid_visual) if source_current else 0, "review": bool(reviewed and source_current),
        "gates_total": len(gates), "gates_ok": sum(v is True for v in gates.values()),
        "gates_failed": [k for k, v in gates.items() if v is not True],
        "report_time": report.get("generated_at", ""), "report_stale": bool(reports and not report),
        "last_change": (run_dir / "ledger.jsonl").stat().st_mtime if (run_dir / "ledger.jsonl").exists() else 0,
    }
