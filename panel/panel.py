"""Panel na żywo dla jednego projektu Systemu v7.0 (Narrative V2).

Tylko odczyt. Panel nie zapisuje niczego w projekcie ani w instalacji:
manifest Advance-Stage obejmuje wszystkie trwałe pliki projektu, a
Test-System skanuje katalog instalacji. Pliki są otwierane z pełnym
współdzieleniem, żeby odczyt nie blokował atomowej podmiany przez narzędzia.

Uruchomienie: Panel.bat (okno wyboru folderu) albo przeciągnięcie folderu
projektu na Panel.bat. Serwer wygasa po godzinie bez kontaktu z panelem.
"""

from __future__ import annotations

import argparse
import copy
from panel_read import FileStore, ReadError, Verifier, inventory, signature, safe_relative, json_load
from panel_k1 import read_run
import heapq
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.parse
import webbrowser
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

_io = threading.local()

HERE = Path(__file__).resolve().parent
PROJECTS_ROOT = HERE.parent / "projects"
V2_REVISION = "2026-08-31_NARRATIVE_V2"
CODEX_SESSIONS = Path.home() / ".codex" / "sessions"
CODEX_INDEX = Path.home() / ".codex" / "session_index.jsonl"
CLAUDE_PROJECTS = Path.home() / ".claude" / "projects"
EDGE = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")

IDLE_EXIT_SECONDS = 3600  # brak kontaktu przez godzinę; odświeżanie wraca po uśpieniu
AGENT_LOOKBACK_SECONDS = 36 * 3600
CODEX_INITIAL_BYTES = 6 * 1024 * 1024
CLAUDE_INITIAL_BYTES = 3 * 1024 * 1024
MAX_LINE_BYTES = 4 * 1024 * 1024

SOURCE_EXT = {".pdf", ".md", ".txt", ".srt", ".vtt"}
SKIP_DIRS = {".git", "__MACOSX", "__pycache__", ".system-v7"}

STAGES = [
    ("W0", "Pomysł i źródła", "Dawid"),
    ("K0", "Pytania i zakres", "Codex"),
    ("K1", "Baza dowodów", "Codex + Dawid"),
    ("K2", "Architektura odcinka", "Codex"),
    ("K2B", "Paczki i suplement", "Codex"),
    ("K3", "Pisanie aktów", "Claude + Codex"),
    ("K4", "Trzy soczewki QA", "Codex"),
    ("K5", "Decyzja Dawida", "Dawid"),
    ("COMPLETE", "Narracja zatwierdzona", "Dawid"),
]
STAGE_KEYS = [key for key, _, _ in STAGES]


# --- odczyt plików -----------------------------------------------------------

from panel_read import shared_open as open_shared


def read_bytes(path, limit=None):
    try:
        with open_shared(path) as handle:
            return handle.read() if limit is None else handle.read(limit)
    except OSError:
        return None


def read_text(path):
    store = getattr(_io, "store", None)
    if store and Path(path).is_relative_to(store.root):
        return store.read(path)
    data = read_bytes(path)
    return None if data is None else data.decode("utf-8-sig", "strict")


def read_json(path):
    store = getattr(_io, "store", None)
    if store and Path(path).is_relative_to(store.root):
        return store.read(path, "json")
    text = read_text(path)
    if text is None:
        return None
    value = json_load(text)
    if not isinstance(value, dict):
        raise ReadError("Oczekiwano obiektu JSON: " + Path(path).name)
    return value


def read_jsonl(path):
    store = getattr(_io, "store", None)
    if store and Path(path).is_relative_to(store.root):
        return store.read(path, "jsonl")
    items = []
    for line in (read_text(path) or "").splitlines():
        if line.strip():
            try:
                value = json_load(line)
                if isinstance(value, dict):
                    items.append(value)
            except ValueError:
                continue
    return items


def mtime(path):
    try:
        return os.stat(path).st_mtime
    except OSError:
        return None


def listdir(path):
    try:
        return os.listdir(path)
    except OSError:
        return []


def subdirs(path):
    try:
        with os.scandir(path) as entries:
            return sorted(Path(e.path) for e in entries if e.is_dir(follow_symlinks=False))
    except OSError:
        return []


_TS_RE = re.compile(r"(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.(\d+))?")


def parse_ts(value):
    try:
        text = str(value or "")
        if not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)?", text):
            return None
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        return parsed.replace(tzinfo=timezone.utc).timestamp() if parsed.tzinfo is None else parsed.timestamp()
    except (ValueError, OverflowError):
        return None


def when(ts):
    return datetime.fromtimestamp(ts).strftime("%d.%m %H:%M") if ts else ""


def short(text, limit=260):
    text = " ".join(str(text or "").split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def plural(n, one, few, many):
    if n == 1:
        return f"{n} {one}"
    if n % 10 in (2, 3, 4) and n % 100 not in (12, 13, 14):
        return f"{n} {few}"
    return f"{n} {many}"


# --- stan projektu -----------------------------------------------------------

def parse_meta(text):
    fields, sections, current = {}, {}, None
    for line in text.splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            sections[current] = []
            continue
        if current is None:
            match = re.match(r"^([A-Z0-9_]+):\s*(.*)$", line)
            if match:
                if match[1] in fields:
                    raise ReadError("Powtórzone pole meta: " + match[1])
                fields[match[1]] = match[2].strip()
        elif line.strip().startswith("- "):
            sections[current].append(line.strip()[2:])
    return fields, sections


def unset(value):
    return value in (None, "", "BRAK", "NIEUSTALONE", "NIEURUCHOMIONA")


def step(label, state, who, detail=""):
    return {"label": label, "state": state, "who": who, "detail": detail}


def cell(state, short_text, detail=""):
    return {"state": state, "short": short_text, "detail": detail or short_text}


class Context:
    def __init__(self, root, meta):
        self.root = root
        self.meta = meta
        self.proofs = getattr(_io, "proofs", None) or {}
        self.store = getattr(_io, "store", None) or FileStore(root, open_shared)
        stage = meta.get("CURRENT_STAGE", "")
        self.blocked = stage == "BLOCKED"
        effective = meta.get("BLOCKED_FROM_STAGE", "") if self.blocked else stage
        self.effective = effective
        self.index = STAGE_KEYS.index(effective) if effective in STAGE_KEYS else -1
        origin = read_json(root / ".system-v7" / "project-origin.json") or {}
        self.created = parse_ts(origin.get("created_at_utc"))
        self.read_errors = []
        self.runs = scan_narrative_runs(root, self.read_errors)
        for run in self.runs:
            check = self.proofs.get("runs", {}).get(run["run_id"], {})
            run["live"] = bool(check.get("bundle_valid"))
            run["valid"] = bool(check.get("valid"))

    def past(self, key):
        return STAGE_KEYS.index(key) < self.index

    def current(self, key):
        return STAGE_KEYS.index(key) == self.index

    def status(self, key, ok, now_state="active"):
        # Etap zamknięty bramką, ale bez śladu w plikach, to "info", nie zielony znacznik.
        if ok:
            return "done"
        if self.past(key):
            return "info"
        return now_state if self.current(key) else "todo"

    def touched(self, path):
        stamp = mtime(path)
        return stamp is not None and (self.created is None or stamp > self.created + 60)

    def run(self, act, run_type):
        matches = [r for r in self.runs if r["act"] == act and r["run_type"] == run_type]
        matches = [r for r in matches if r.get("live")]
        return matches[0] if len(matches) == 1 else None

    def latest_run(self, run_type):
        matches = [r for r in self.runs if r["run_type"] == run_type]
        matches = [r for r in matches if r.get("live")]
        return matches[0] if len(matches) == 1 else None


K3_RUN_TYPES = {"CONSTRAINT_ATOMICITY_PREFLIGHT", "GENERATE_ACT", "BEAT_PREFLIGHT", "CONTINUITY_ATTEST"}


def scan_narrative_runs(root, errors=None):
    runs = []
    for run_dir in subdirs(root / "_work" / "narrative-runs"):
        try:
            names = set(listdir(run_dir))
            manifest = read_json(run_dir / "input-manifest.json") if "input-manifest.json" in names else None
            receipt = read_json(run_dir / "run-receipt.json") if "run-receipt.json" in names else None
            if manifest is None and receipt is None:
                continue
            run_type = (manifest or receipt or {}).get("run_type", "?")
            act = None
            if run_type in K3_RUN_TYPES:
                match = re.search(r"ACT[-_.]?(\d{3})", run_dir.name.upper())
                if not match and manifest:
                    match = re.search(r"ACT-(\d{3})", json.dumps(manifest.get("entries", [])))
                act = f"ACT-{match.group(1)}" if match else None
            outputs = [n for n in names if n.startswith("output.")]
            stamps = [mtime(run_dir / n) for n in names if n in ("input-manifest.json", "run-receipt.json") or n in outputs]
            runs.append({
                "run_id": run_dir.name,
                "run_type": run_type,
                "act": act,
                "bundle": manifest is not None,
                "output": bool(outputs),
                "verdict": output_verdict(root, receipt, run_dir, outputs),
                "receipt": receipt is not None,
                "receipt_relative": f"_work/narrative-runs/{run_dir.name}/run-receipt.json",
                "actor": "CLAUDE" if run_type == "GENERATE_ACT" else "CODEX",
                "mtime": max([s for s in stamps if s] or [0]),
            })
        except (OSError, ValueError, TypeError, AttributeError) as exc:
            if errors is None:
                raise
            errors.append(f"Run {run_dir.name}: {exc}")
    return runs


def run_cell(run, waiting_text):
    if run.get("verdict") == "FAIL":
        return cell("fail", "FAIL", f"{run['run_id']}: odpowiedź z werdyktem FAIL")
    if run["receipt"]:
        return cell("info", "receipt", f"{run['run_id']}: receipt zapisany; krok wymaga importu/akceptacji")
    if run["output"]:
        return cell("active", "odpowiedź", f"{run['run_id']}: odpowiedź zapisana, brak receiptu")
    return cell("active", waiting_text, f"{run['run_id']}: bundle gotowy, czeka na odpowiedź")


def active_sources(root):
    folder = root / "sources"
    files = [n for n in listdir(folder) if Path(n).suffix.lower() in SOURCE_EXT and (folder / n).is_file()]
    pdfs = [n for n in files if n.lower().endswith(".pdf")]
    twins = {n[:-4].lower() + "--text.md" for n in pdfs}
    logical = len(pdfs) + len([n for n in files if not n.lower().endswith(".pdf") and n.lower() not in twins])
    return files, logical


def stage_w0(ctx):
    files, logical = active_sources(ctx.root)
    kinds = {}
    for name in files:
        ext = Path(name).suffix.lower().lstrip(".").upper()
        kinds[ext] = kinds.get(ext, 0) + 1
    summary = ", ".join(f"{count} {ext}" for ext, count in sorted(kinds.items()))
    decision = ctx.meta.get("W0_DECISION", "")
    steps = [
        step("Materiały w sources/", ctx.status("W0", bool(files), "wait"), "DAWID",
             f"{plural(logical, 'źródło', 'źródła', 'źródeł')} ({summary})" if files else "brak plików PDF/MD/TXT/SRT/VTT"),
        step("Decyzja W0", ctx.status("W0", not unset(decision), "wait"), "DAWID",
             decision if not unset(decision) else "jeszcze nie podjęta"),
    ]
    if not unset(ctx.meta.get("W0_CONDITIONS")):
        closed = not unset(ctx.meta.get("W0_CONDITION_RESULT"))
        steps.append(step("Zamknięcie warunku W0", "done" if closed else "wait", "DAWID",
                          f"{ctx.meta.get('W0_CONDITIONS')} · {ctx.meta.get('W0_CONDITION_STATUS', '')}"))
    return steps, None


def stage_k0(ctx):
    fundament = ctx.root / "00-fundament-projektu.md"
    edited = ctx.touched(fundament)
    policy = not unset(ctx.meta.get("DURATION_POLICY_RECEIPT_PATH"))
    steps = [
        step("Fundament projektu (00-fundament-projektu.md)", ctx.status("K0", edited and ctx.past("K0")), "CODEX",
             f"zmieniony {when(mtime(fundament))}" if edited else "jeszcze szablon"),
        step("Polityka czasu", "done" if policy else "info", "DAWID",
             f"{ctx.meta.get('TARGET_MINUTES', '?')} min · {ctx.meta.get('TARGET_DURATION_MODE', '?')}"
             + (" · receipt zmiany" if policy else "")),
    ]
    return steps, None


def k1_run_state(run_dir):
    store = getattr(_io, "store", None)
    if store is None:
        root = run_dir.parents[3]
        store = FileStore(root, open_shared)
    return read_run(run_dir, store.root, store)


def stage_k1(ctx):
    base = ctx.root / "_work" / "K1" / "k1-lite-v2"
    all_runs = [k1_run_state(d) for d in subdirs(base) if (d / "chunks.jsonl").exists()]
    runs, plan_complete, mapping_detail = current_source_runs(ctx, all_runs)
    _, logical = active_sources(ctx.root)
    total = sum(r["chunks_total"] for r in runs)
    done = sum(r["chunks_done"] for r in runs)
    waiting = sum(len(r["waiting"]) for r in runs)
    candidates = sum(r["candidates"] for r in runs)
    decided = sum(r["decided"] for r in runs)
    selected = sum(r["selected"] for r in runs)
    recommendations = sum(r["recommendations"] for r in runs)
    analysis_done = bool(total) and done == total
    receipt = ctx.meta.get("K1_PUBLISH_RECEIPT_PATH", "")
    published = ctx.proofs.get("publication", {}).get("valid", False)

    def state(ok, now_state):
        return ctx.status("K1", bool(ok), now_state)

    steps = [
        step("Plan runów (jeden run na źródło)", state(plan_complete, "active" if runs else "todo"),
             "CODEX", f"{plural(len(runs), 'run', 'runy', 'runów')} · {plural(logical, 'źródło', 'źródła', 'źródeł')} w sources/ · {mapping_detail}"),
        step("Analiza całego korpusu przez workera", state(analysis_done, "active" if runs else "todo"), "CODEX",
             f"{done} z {total} paczek" + (f" · czeka na workera: {waiting}" if waiting else "")),
        step("Rekomendacje ChatGPT (KEY_CHATGPT)", state(candidates and recommendations + decided >= candidates, "active" if analysis_done else "todo"), "CODEX",
             f"{recommendations} z {candidates} kandydatów z rekomendacją"),
        step("Decyzje Dawida: MUST_INCLUDE / IMPORTANT_SIDE / REJECTED",
             state(candidates and decided >= candidates, "info"), "DAWID",
             f"{decided} z {candidates} kandydatów · wybrane: {selected}"),
    ]
    visual_runs = [r for r in runs if r["visual_required"]]
    if visual_runs:
        needed = sum(r["selected"] for r in visual_runs)
        have = sum(r["visual"] for r in visual_runs)
        steps.append(step("Visual QA wybranych cytatów", state(have >= needed, "active" if needed else "info"),
                          "CODEX", f"{have} z {needed} cytatów z PDF"))
    reviewed = sum(1 for r in runs if r["review"])
    steps.append(step("Przegląd editorial-review.md", state(runs and reviewed == len(runs), "wait" if selected else "todo"),
                      "DAWID", f"receipt Dawida w {reviewed} z {len(runs)} runów"))
    gates_ok = runs and all(r["gates_total"] and not r["gates_failed"] and not r["report_stale"] for r in runs)
    failed = [f"{r['name']}: {', '.join(r['gates_failed'])}" for r in runs if r["gates_failed"]]
    stale = [r["name"] for r in runs if r["report_stale"]]
    if published and plan_complete and all(r["source_current"] for r in runs):
        gate_state, gate_detail = "done", "Bramki potwierdzone bieżącą publikacją; raporty pojedynczych runów mogą być historyczne"
    else:
        gate_detail = "; ".join(failed) if failed else "wszystkie runy mają komplet bramek" if gates_ok else "brak raportu ValidateRun"
        if stale:
            gate_detail += " · raport niezgodny z bieżącymi wejściami: " + ", ".join(stale)
        gate_state = state(gates_ok, "fail" if failed else "active" if runs else "todo")
    steps.append(step("Sześć bramek runu (ValidateRun)", gate_state, "SYSTEM", gate_detail))
    steps.append(step("Preview → Publish 01-baza-dowodow.md", state(published, "todo"), "SYSTEM",
                      f"opublikowano {when(mtime(ctx.root / receipt))}" if published else "jeszcze nie opublikowano"))
    if not unset(ctx.meta.get("K1_MANUAL_REASON")):
        steps.append(step("Manual fallback K1 (zgoda Dawida)", "info", "DAWID", ctx.meta["K1_MANUAL_REASON"]))
    runs.sort(key=lambda r: r["last_change"], reverse=True)
    return steps, {"runs": runs}


def stage_k2(ctx):
    architecture = ctx.root / "02-architektura-odcinka.md"
    author_texts = [n for n in listdir(ctx.root / "_work" / "k2" / "author-text") if n.endswith(".json")]
    sequence = ctx.meta.get("NARRATIVE_ACT_SEQUENCE", "")
    steps = [
        step("Story Engine V2 (02-architektura-odcinka.md)", ctx.status("K2", ctx.past("K2") and ctx.touched(architecture)), "CODEX",
             f"zmieniona {when(mtime(architecture))}" if ctx.touched(architecture) else "jeszcze szablon"),
        step("Dokładne AUTHOR_TEXT zatwierdzone przez Dawida", "done" if author_texts else "info", "DAWID",
             plural(len(author_texts), "receipt", "receipty", "receiptów") if author_texts else "brak receiptów AUTHOR_TEXT"),
        step("Sekwencja aktów", ctx.status("K2", not unset(sequence)), "CODEX",
             sequence if not unset(sequence) else "jeszcze nieustalona"),
    ]
    return steps, None


def stage_k2b(ctx):
    meta = ctx.meta
    voice = meta.get("VOICE_PROFILE_STATUS", "")
    model = meta.get("K3_MODEL_ID", "")
    prefix = ctx.root / "_work" / "k3" / "prefix" / "prefix.manifest.json"
    steps = [
        step("Decyzja K2B: czy potrzebny suplement", ctx.status("K2B", not unset(meta.get("K2B_DECISION"))),
             "CODEX", meta.get("K2B_DECISION", "")),
        step("Profil głosu zatwierdzony", ctx.status("K2B", voice == "APPROVED", "wait"), "DAWID",
             f"{meta.get('VOICE_PROFILE_REVISION', '')} · {voice}"),
        step("Zamrożony model K3", ctx.status("K2B", not unset(model)), "CODEX",
             f"{model} · {meta.get('K3_MODEL_REVISION', '')}" if not unset(model) else "jeszcze nieustalony"),
        step("Stable prefix K3", ctx.status("K2B", prefix.exists()), "SYSTEM",
             f"zbudowany {when(mtime(prefix))}" if prefix.exists() else "jeszcze niezbudowany"),
    ]
    return steps, None


ACT_COLUMNS = [("packet", "Paczka", "SYSTEM"), ("preflight", "Constraint preflight", "CODEX"),
               ("beat", "Beat preflight", "CODEX"), ("prose", "Claude pisze akt", "CLAUDE"),
               ("out", "CONTINUITY_OUT", "CLAUDE"), ("attest", "Atest ciągłości", "CODEX")]


def act_row(ctx, act):
    k3 = ctx.root / "_work/k3"
    packet = read_json(k3 / "packets" / f"{act}.packet.json") or {}
    core = read_json(k3 / "packets" / f"{act}.act-packet.json") or {}
    preflight = read_json(k3 / "packets" / f"{act}.constraint-preflight.json") or {}
    beat = read_json(k3 / "beats" / act / "state.json") or {}
    state = read_json(k3 / "acts" / act / "state.json") or {}
    attest = read_json(k3 / "continuity" / f"{act}.attest.json") or {}
    checked = ctx.proofs.get("acts", {}).get(act, {})
    store = ctx.store
    def bound(rel, sha):
        return store.bound(rel, sha)
    def run_valid(relative, sha=None):
        if not relative:
            return False
        run_id = Path(relative).parent.name
        return bool(ctx.proofs.get("runs", {}).get(run_id, {}).get("valid")) and (not sha or bound(relative, sha))
    model_current = (packet.get("prefix_sha256") == ctx.meta.get("K3_PREFIX_SHA256")
        and packet.get("model_id") == ctx.meta.get("K3_MODEL_ID")
        and packet.get("model_revision") == ctx.meta.get("K3_MODEL_REVISION")
        and bool(packet.get("prefix_sha256")))
    pre_ok = (preflight.get("status") == "PASS" and preflight.get("act_id") == act
        and preflight.get("packet_sha256") == packet.get("packet_sha256")
        and bound(f"_work/k3/packets/{act}.packet.md", packet.get("packet_sha256"))
        and bound(f"_work/k3/packets/{act}.constraint-ledger.json", preflight.get("constraint_ledger_sha256"))
        and bound(f"_work/k3/packets/{act}.narrative-action-registry.json", packet.get("narrative_action_registry_sha256"))
        and run_valid(preflight.get("run_receipt_relative"), preflight.get("run_receipt_sha256"))
        and model_current)
    cells = {}
    cells["packet"] = cell("done", "READY") if pre_ok and packet.get("status") == "READY" else cell("info" if packet else "todo", packet.get("status", "brak"), "Paczka zapisana; kontrola aktualności i preflight")
    run = ctx.run(act, "CONSTRAINT_ATOMICITY_PREFLIGHT")
    cells["preflight"] = cell("done", "PASS") if pre_ok else cell("fail", "FAIL") if preflight.get("status") == "FAIL" else run_cell(run, "Codex ocenia") if run else cell("info" if preflight else "todo", "niepotwierdzony" if preflight else "brak")
    complex_act = core.get("complexity_flag") == "COMPLEX"
    beat_ok = (pre_ok and beat.get("status") == "BEAT_PREFLIGHT_PASS"
        and beat.get("prefix_sha256") == packet.get("prefix_sha256")
        and bound(f"_work/k3/beats/{act}/beat-sheet.json", beat.get("beat_sheet_sha256"))
        and run_valid(beat.get("preflight_receipt_relative"), beat.get("preflight_receipt_sha256")))
    cells["beat"] = cell("done", "PASS") if beat_ok else cell("na", "SIMPLE") if core.get("complexity_flag") == "SIMPLE" else cell("todo" if not beat else "info", "wymagany" if complex_act else "nieustalony")
    act_model = model_current and state.get("prefix_sha256") == packet.get("prefix_sha256") and state.get("model_id") == packet.get("model_id") and state.get("model_revision") == packet.get("model_revision")
    prose_ok = bool(checked.get("prose", {}).get("valid")) and act_model and pre_ok and (not complex_act or beat_ok) and bound(f"_work/k3/acts/{act}/blocks.json", state.get("blocks_sha256"))
    run = ctx.run(act, "GENERATE_ACT")
    cells["prose"] = cell("fail", "PACKET_INSUFFICIENT") if state.get("status") == "PACKET_INSUFFICIENT" else cell("done", "zaimportowana") if prose_ok else cell("info", "zapisana, niepotwierdzona") if (k3 / "acts" / act / "prose.md").exists() else run_cell(run, "Claude pisze") if run else cell("todo", "brak")
    out_ok = prose_ok and state.get("status") in ("AWAITING_ATTEST", "ATTESTED") and bound(f"_work/k3/acts/{act}/out.json", state.get("continuity_out_sha256")) and run_valid(state.get("generate_run_receipt_relative"), state.get("generate_run_receipt_sha256"))
    cells["out"] = cell("done", "zapisane") if out_ok else cell("info", "niepotwierdzone") if (k3 / "acts" / act / "out.json").exists() else cell("todo", "brak")
    attest_ok = bool(checked.get("attest", {}).get("valid")) and out_ok
    check = checked.get("attest", {})
    run = ctx.run(act, "CONTINUITY_ATTEST")
    cells["attest"] = cell("done", "PASS") if attest_ok else cell("info" if ctx.proofs.get("pending") else "fail", "niepotwierdzony", "; ".join(check.get("errors", [])) or "Wymagana kontrola zależności") if attest else run_cell(run, "Codex atestuje") if run else cell("wait" if out_ok else "todo", "brak")
    return {"act": act, "cells": cells, "attested": attest_ok}


def stage_k3(ctx):
    k3 = ctx.root / "_work" / "k3"
    sequence = [a.strip() for a in ctx.meta.get("NARRATIVE_ACT_SEQUENCE", "").split(",") if re.fullmatch(r"ACT-\d{3}", a.strip())]
    found = {m.group(1) for n in listdir(k3 / "packets") if (m := re.match(r"(ACT-\d{3})\.packet\.json$", n))}
    found |= {d.name for d in subdirs(k3 / "acts") if re.fullmatch(r"ACT-\d{3}", d.name)}
    acts = sequence + sorted(found - set(sequence))
    rows = [act_row(ctx, act) for act in acts]
    attested = sum(1 for r in rows if r["attested"])
    steps = [step("Akty z ważnym atestem ciągłości", ctx.status("K3", rows and attested == len(rows)), "CODEX",
                  f"{attested} z {len(rows)} · CONTINUITY_STATUS: {ctx.meta.get('CONTINUITY_STATUS', '?')}")]
    for row in rows:
        if row["attested"]:
            continue
        row["current"] = True
        for key, label, who in ACT_COLUMNS:
            item = row["cells"][key]
            if item["state"] not in ("done", "na"):
                state = item["state"] if item["state"] != "todo" else ("active" if ctx.current("K3") else "todo")
                steps.append(step(f"Teraz {row['act']}: {label}", state, who, item["detail"]))
                break
        break
    assemblies = [n for n in listdir(k3 / "assembly") if n.endswith(".json")]
    draft = ctx.root / "03-draft.md"
    steps.append(step("Montaż 03-draft.md (Assemble-K3Draft)", ctx.status("K3", ctx.proofs.get("assembly", {}).get("valid", False), "info" if assemblies else "todo"),
                      "SYSTEM", "Montaż i aktualne akty potwierdzone" if ctx.proofs.get("assembly", {}).get("valid") else "Zapisany montaż wymaga kontroli powiązań" if assemblies else "po atestach wszystkich aktów"))
    return steps, {"acts": rows}


LENSES = [("EDITOR", "Editor V2", "K4_EDITOR_PROOF"), ("VERIFY", "Verify source-first", "K4_VERIFY_PROOF"),
          ("COLD_READER", "Cold Reader (audio-only)", "K4_COLD_READER_PROOF")]


def stage_k4(ctx):
    steps = []
    for run_type, label, pointer in LENSES:
        relative = ctx.meta.get(pointer, "")
        check = ctx.proofs.get("lenses", {}).get(run_type, {})
        if not unset(relative):
            status = "done" if check.get("valid") else "info" if ctx.proofs.get("pending") else "fail"
            detail = "Bieżący dowód potwierdzony" if status == "done" else "Kontrola powiązanego dowodu: " + "; ".join(check.get("errors", []))
            steps.append(step(label, status, "CODEX", detail))
            # A fresh negative attempt must remain visible alongside a previously bound proof.
            newer = [r for r in ctx.runs if r["run_type"] == run_type and r["receipt_relative"] != relative and r.get("live")]
            for r in newer:
                if r.get("verdict") == "FAIL":
                    steps.append(step(label + " — nowa próba", "fail", "CODEX", r["run_id"] + ": FAIL"))
            continue
        runs = [r for r in ctx.runs if r["run_type"] == run_type and r.get("live")]
        if not runs:
            steps.append(step(label, ctx.status("K4", False, "todo"), "CODEX", "brak bieżącego dowodu; zapisane próby wymagają kontroli" if ctx.runs else "run jeszcze nie utworzony"))
        elif len(runs) > 1:
            steps.append(step(label, "info", "CODEX", "Kilka bieżących prób; brak wskazania dowodu w meta"))
            for r in runs:
                if r.get("verdict") == "FAIL":
                    steps.append(step(label + " — próba", "fail", "CODEX", r["run_id"] + ": FAIL"))
        else:
            r = runs[0]
            verdict = r.get("verdict")
            status = "fail" if verdict == "FAIL" else "info" if r["receipt"] else "active"
            steps.append(step(label, status, "CODEX", f"{r['run_id']}: {verdict or 'oczekuje'}; dowód jeszcze niewpięty w meta"))
    sha = ctx.meta.get("K4_PROOF_SET_SHA256", "")
    check = ctx.proofs.get("k4", {})
    status = "done" if check.get("valid") else "info" if ctx.proofs.get("pending") else "fail" if not unset(sha) else "todo"
    steps.append(step("Proof set K4 → 04-raport-qa.md i 04B-fact-check.md", status, "SYSTEM",
        "Potwierdzony względem bieżącego draftu" if check.get("valid") else "; ".join(check.get("errors", [])) or "Oczekuje na potwierdzenie bieżącego zestawu"))
    return steps, None


def stage_k5(ctx):
    final = ctx.root / "05-FINAL-SCRIPT.md"
    check = ctx.proofs.get("k5", {})
    valid = check.get("valid", False)
    approvals = [n for n in listdir(ctx.root / "_work/K5") if n.startswith("v2-approval-")]
    state = "done" if valid else "info" if ctx.proofs.get("pending") else "fail" if approvals else "wait" if ctx.current("K5") else "todo"
    return [
        step("Finalna narracja 05-FINAL-SCRIPT.md", "done" if valid else "info" if final.exists() else "todo",
             "CODEX", "Final i powiązania potwierdzone" if valid else "Zapisany plik nie potwierdza akceptacji bieżącej narracji"),
        step("Akceptacja Dawida (Approve-K5FinalV2)", state, "DAWID",
             "Ważna dla bieżącego finalu" if valid else "; ".join(check.get("errors", [])) or "Brak potwierdzonej bieżącej akceptacji")
    ], None


def stage_complete(ctx):
    declared = ctx.meta.get("CURRENT_STAGE") == "COMPLETE"
    valid = declared and ctx.meta.get("LAST_GATE") == "K5_PASS" and ctx.proofs.get("k5", {}).get("valid", False)
    return [step("Advance-Stage → COMPLETE / K5_PASS", "done" if valid else "info" if declared else "todo",
        "SYSTEM", "Bieżąca akceptacja potwierdzona; meta: COMPLETE" if valid else "Deklaracja meta nie zastępuje ważnej akceptacji K5")], None


BUILDERS = {"W0": stage_w0, "K0": stage_k0, "K1": stage_k1, "K2": stage_k2, "K2B": stage_k2b,
            "K3": stage_k3, "K4": stage_k4, "K5": stage_k5, "COMPLETE": stage_complete}


def _collect_project(root):
    text = read_text(root / "meta.md")
    if text is None:
        return {"ok": False, "error": f"Nie mogę odczytać {root / 'meta.md'}"}
    meta, sections = parse_meta(text)
    validate_meta(meta)
    ctx = Context(root, meta)
    stages = []
    for i, (key, title, owner) in enumerate(STAGES):
        if i < ctx.index:
            status = "done"
        elif key == "COMPLETE" and i == ctx.index:
            status = "done" if ctx.proofs.get("k5", {}).get("valid") and meta.get("LAST_GATE") == "K5_PASS" else "blocked"
        elif i == ctx.index:
            status = "blocked" if ctx.blocked else "current"
        else:
            status = "todo"
        try:
            steps, extra = BUILDERS[key](ctx)
        except Exception as exc:  # jeden nieczytelny etap nie może wyłączyć panelu
            steps, extra = [step("Nie udało się odczytać etapu", "fail", "SYSTEM", f"{type(exc).__name__}: {exc}")], None
        if any(s["state"] == "fail" for s in steps):
            status = "blocked"
        stages.append({"key": key, "title": title, "owner": owner, "status": status,
                       "historical": i < ctx.index, "steps": steps, "extra": extra})

    waiting = [f"{s['key']}: {st['label']}" for s in stages if s["status"] in ("current", "blocked")
               for st in s["steps"] if st["who"] == "DAWID" and st["state"] == "wait"]
    pending = [{"run_id": r["run_id"], "run_type": r["run_type"], "actor": r["actor"], "mtime": r["mtime"],
                "what": "odpowiedź zapisana, brak receiptu" if r["output"] else "bundle gotowy, czeka na odpowiedź"}
               for r in sorted(ctx.runs, key=lambda r: r["mtime"], reverse=True) if r["bundle"] and not r["receipt"] and r.get("live")]
    k1 = next((s["extra"] for s in stages if s["key"] == "K1" and s["extra"]), None)
    for run in (k1 or {}).get("runs", []):
        for task in run.get("tasks", []):
            pending.append({"run_id": f"K1 {run['name']}", "run_type": "K1_WORK", "actor": "CODEX",
                            "mtime": run["last_change"], "what": f"{task['status']}: {task['detail']}"})
    return {
        "ok": True,
        "read_errors": ctx.read_errors,
        "partial": bool(ctx.read_errors) or any(any(x["label"] == "Nie udało się odczytać etapu" for x in st["steps"]) for st in stages),
        "project": {"name": meta.get("PROJECT_NAME") or root.name, "path": str(root),
                    "revision": meta.get("WORKFLOW_REVISION", ""), "activation": meta.get("WORKFLOW_ACTIVATION", "")},
        "stage": {
            "current": meta.get("CURRENT_STAGE", ""), "effective": ctx.effective, "blocked": ctx.blocked,
            "blocked_reason": meta.get("BLOCKED_REASON", ""), "last_gate": meta.get("LAST_GATE", ""),
            "owner": meta.get("STAGE_OWNER", ""), "override": meta.get("OWNER_OVERRIDE", ""),
            "next_action": meta.get("NEXT_ACTION", ""), "updated": meta.get("LAST_UPDATED", ""),
            "meta_changed": mtime(root / "meta.md"),
        },
        "handoff": sections.get("AKTYWNY HANDOFF", []),
        "risks": [r for r in sections.get("AKTYWNE RYZYKA", []) if r != "BRAK"],
        "history": sections.get("ARCHIWUM ZMIAN", [])[-6:][::-1],
        "stages": stages,
        "waiting_for_dawid": waiting,
        "pending_runs": pending,
    }


ACT_FILE_LABELS = {"prose.md": "proza zaimportowana", "blocks.json": "bloki prozy", "out.json": "CONTINUITY_OUT zapisane",
                   "state.json": "zmiana stanu aktu", "continuity-out-request.md": "prośba o CONTINUITY_OUT"}


def file_label(rel):
    parts = rel.split("/")
    name = parts[-1]
    if rel == "meta.md":
        return "meta.md — zmiana stanu projektu"
    if len(parts) == 1:
        return name
    if parts[:2] == ["_work", "narrative-runs"] and len(parts) >= 4:
        run = parts[2]
        if name == "input-manifest.json":
            return f"{run}: przygotowano bundle wejść"
        if name == "run-receipt.json":
            return f"{run}: receipt runu"
        if name.startswith("output."):
            return f"{run}: zapisano odpowiedź modelu"
        return f"{run}: {'/'.join(parts[3:])}"
    if parts[:3] == ["_work", "k3", "acts"] and len(parts) == 5:
        return f"{parts[3]}: {ACT_FILE_LABELS.get(name, name)}"
    if parts[:3] == ["_work", "k3", "continuity"]:
        match = re.match(r"(ACT-\d{3})\.(.+)$", name)
        return f"{match.group(1)}: ciągłość ({match.group(2)})" if match else f"ciągłość: {name}"
    if parts[:3] == ["_work", "k3", "packets"]:
        match = re.match(r"(ACT-\d{3})\.(.+)$", name)
        return f"{match.group(1)}: paczka ({match.group(2)})" if match else f"paczki K3: {name}"
    if parts[:3] == ["_work", "K1", "k1-lite-v2"] and len(parts) >= 5:
        return f"K1 {parts[3]}: {'/'.join(parts[4:])}"
    if parts[:2] == ["_work", "K5"]:
        return "K5: receipt akceptacji Dawida"
    if parts[:3] == ["_work", "k4", "proof-sets"]:
        return "K4: proof set"
    if parts[:2] == ["_work", "system"]:
        return f"receipt systemu: {'/'.join(parts[2:])}"
    return rel


def recent_files(root, limit=30):
    def entries():
        for directory, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and d != "_oryginaly"
                           and not (Path(directory) / d).is_symlink()
                           and not (getattr((Path(directory) / d).lstat(), "st_file_attributes", 0) & 1024)]
            for name in filenames:
                path = os.path.join(directory, name)
                stamp = mtime(path)
                if stamp:
                    yield stamp, os.path.relpath(path, root).replace("\\", "/")
    return [{"ts": stamp, "src": "PLIK", "kind": "file", "text": rel,
             "detail": "Czas modyfikacji pliku; nie potwierdza wykonania ani akceptacji kroku"}
            for stamp, rel in heapq.nlargest(limit, entries())]


# --- sesje Codexa i Claude'a -------------------------------------------------

def norm(text):
    text = str(text or "").replace("\\", "/").lower()
    return urllib.parse.unquote(text) if "%" in text else text


class Tail:
    """Bounded append reader. Replacement/truncation resets context and partial bytes."""
    def __init__(self, path, initial_bytes):
        self.path, self.initial = path, initial_bytes
        self.offset = None
        self.buffer = b""
        self.skip_partial = False
        self.identity = None
        self.last_sig = None
        self.anchor = b""
        self.generation = 0

    def read_new(self):
        sig = signature(self.path)
        if sig is None:
            return []
        ident, size = sig[:2], sig[2]
        replaced = self.identity is not None and (self.identity != ident or size < self.offset or
                    (size == self.offset and sig != self.last_sig))
        with open_shared(self.path) as handle:
            if not replaced and self.offset and self.anchor and sig != self.last_sig:
                handle.seek(self.offset - len(self.anchor))
                replaced = handle.read(len(self.anchor)) != self.anchor
            if replaced:
                self.offset, self.buffer, self.skip_partial = 0, b"", False
                self.generation += 1
            if self.offset is None:
                self.offset = max(0, size - self.initial)
                if self.offset:
                    handle.seek(self.offset - 1)
                    self.skip_partial = handle.read(1) != b"\n"
            self.identity, self.last_sig = ident, sig
            if size == self.offset:
                return []
            handle.seek(self.offset)
            data = handle.read(min(size - self.offset, 16 * 1024 * 1024))
            self.offset += len(data)
            anchor_start = max(0, self.offset - 128)
            handle.seek(anchor_start)
            self.anchor = handle.read(self.offset - anchor_start)
        lines = (self.buffer + data).split(b"\n")
        self.buffer = lines.pop()
        if self.skip_partial:
            if lines:
                lines.pop(0)
                self.skip_partial = False
            else:
                self.buffer = b""
                return []
        complete = [line.removesuffix(b"\r") for line in lines if len(line) <= MAX_LINE_BYTES]
        if len(self.buffer) > MAX_LINE_BYTES:
            self.buffer = b""
            self.skip_partial = True
        return complete


def mtime_size(path):
    try:
        return os.stat(path).st_size
    except OSError:
        return None


class Session:
    def __init__(self, source, path, initial_bytes):
        self.source, self.path = source, path
        self.tail = Tail(path, initial_bytes)
        self.title, self.events = "", []
        self.linked = self.context = self.base_context = False
        self.skip = self.working = self.started = False
        self.last_ts = 0.0
        self.turn = 0
        self.messages = {}
        self.generation = 0
        self.seen_at = time.time()


class AgentWatcher:
    def __init__(self, project_root):
        root = norm(str(project_root)).rstrip("/")
        self.project = root
        keys = {root}
        self.patterns = [re.compile(re.escape(k) + r"(?![\w\-])") for k in keys]
        self.sessions = {}
        self.last_scan = 0.0
        self.codex_titles = {}
        self.index_mtime = None
        self.errors = []

    def mentions(self, text):
        if isinstance(text, dict):
            return any(self.mentions(v) for v in text.values())
        if isinstance(text, (list, tuple)):
            return any(self.mentions(v) for v in text)
        if isinstance(text, str) and text.lstrip().startswith(("{", "[")):
            try:
                return self.mentions(json.loads(text))
            except ValueError:
                pass
        text = norm(text)
        return any(p.search(text) for p in self.patterns)

    def inside(self, cwd):
        cwd = norm(urllib.parse.unquote(cwd or "")).rstrip("/")
        if cwd.startswith("//?/unc/"):
            cwd = "//" + cwd[8:]
        elif cwd.startswith("//?/"):
            cwd = cwd[4:]
        for prefix in ("file:///", "file://"):
            if cwd.startswith(prefix):
                cwd = cwd[len(prefix):]
        return cwd == self.project or cwd.startswith(self.project + "/")

    def poll(self, now):
        self.errors = []
        if time.monotonic() - self.last_scan > 60:
            self.discover(now)
            self.last_scan = time.monotonic()
        for session in list(self.sessions.values()):
            if session.skip:
                continue
            try:
                raws = session.tail.read_new()
            except OSError as exc:
                session.working = False
                self.errors.append(f"Log {session.source}: {exc}")
                continue
            if session.generation != session.tail.generation:
                session.events.clear()
                session.context = session.base_context = session.linked = session.working = False
                session.generation = session.tail.generation
            for raw in raws:
                if not raw.strip() or len(raw) > MAX_LINE_BYTES:
                    continue
                try:
                    if session.source == "CODEX":
                        self.codex_line(session, raw)
                    else:
                        self.claude_line(session, raw)
                except (ValueError, AttributeError, TypeError):
                    continue
            del session.events[:-400]

    def discover(self, now):
        self.sessions = {k:s for k,s in self.sessions.items() if now - (mtime(s.path) or 0) <= AGENT_LOOKBACK_SECONDS}
        stamp = mtime(CODEX_INDEX)
        if stamp != self.index_mtime:
            self.index_mtime = stamp
            for item in read_jsonl(CODEX_INDEX):
                if item.get("id") and item.get("thread_name"):
                    self.codex_titles[item["id"]] = item["thread_name"]
        for directory, _, filenames in os.walk(CODEX_SESSIONS):
            for name in filenames:
                if name.endswith(".jsonl"):
                    self.consider("CODEX", os.path.join(directory, name), now, CODEX_INITIAL_BYTES)
        for project_dir in subdirs(CLAUDE_PROJECTS):
            for name in listdir(project_dir):
                if name.endswith(".jsonl"):
                    self.consider("CLAUDE", str(project_dir / name), now, CLAUDE_INITIAL_BYTES)
        for session in self.sessions.values():
            if session.source == "CODEX" and not session.title:
                match = re.search(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$", session.path)
                session.title = self.codex_titles.get(match.group(1), "") if match else ""

    def consider(self, source, path, now, initial_bytes):
        if path in self.sessions:
            return
        if len(self.sessions) >= 128:
            oldest = min(self.sessions, key=lambda k: mtime(self.sessions[k].path) or 0)
            if (mtime(path) or 0) <= (mtime(self.sessions[oldest].path) or 0):
                return
            del self.sessions[oldest]
        stamp = mtime(path)
        if not stamp or now - stamp > AGENT_LOOKBACK_SECONDS:
            return
        session = Session(source, path, initial_bytes)
        if source == "CODEX":
            head = (read_bytes(path, 65536) or b"").split(b"\n", 1)[0]
            session.skip = b'"guardian_review"' in head or b'"subagent"' in head
            try:
                obj = json.loads(head)
                session.base_context = self.inside((obj.get("payload") or {}).get("cwd", ""))
                session.context = session.base_context
            except (ValueError, AttributeError):
                pass
        self.sessions[path] = session

    def add(self, session, ts, kind, text, relevance="", failed=False):
        if not text:
            return
        if relevance and self.mentions(relevance):
            session.context = True
        if not session.context:
            return
        session.linked = True
        session.working = session.started
        if ts:
            session.last_ts = max(session.last_ts, ts)
        session.events.append({"ts": ts or session.last_ts, "src": session.source, "kind": kind,
                               "text": short(text), "failed": failed})

    def message(self, session, ts, kind, text, variant):
        if not isinstance(text, str):
            return
        if kind == "prompt":
            if self.mentions(text):
                session.context = True
            elif re.search(r"(?:[A-Za-z]:[\\/]|file://)", text):
                session.context = False
                session.working = False
        key = (kind, text)
        previous = session.messages.get(key)
        if previous and previous[0] != variant and abs((ts or 0) - previous[1]) < 5:
            return
        if len(session.messages) > 400:
            session.messages.clear()
        session.messages[key] = (variant, ts or 0)
        self.add(session, ts, kind, text, text)

    def codex_line(self, session, raw):
        obj = json.loads(raw)
        payload = obj.get("payload") or {}
        ts = parse_ts(obj.get("timestamp"))
        kind = obj.get("type")
        if kind in ("turn_context", "session_meta"):
            if kind == "session_meta" and (payload.get("thread_source") == "guardian_review"
                                           or "subagent" in (payload.get("source") or {})):
                session.skip = True
            if "cwd" in payload:
                session.base_context = self.inside(payload["cwd"])
                session.context = session.base_context
                if not session.context:
                    session.working = False
            return
        event = payload.get("type")
        if event == "task_started":
            session.turn += 1
            session.messages.clear()
            session.context = session.base_context
            session.started = True
            session.working = session.context
            if session.context and ts:
                session.last_ts = ts
                session.linked = True
        elif event == "task_complete":
            if session.context and ts:
                session.last_ts = ts
            session.working = session.started = False
        elif event == "turn_aborted":
            session.working = session.started = False
            self.add(session, ts, "stop", "Tura przerwana")
        elif event in ("user_message", "agent_message"):
            text = payload.get("message") or payload.get("text") or ""
            self.message(session, ts, "prompt" if event == "user_message" else "say", text, event)
        elif event == "item_completed":
            item = payload.get("item") or {}
            item_type = item.get("type")
            if item_type in ("UserMessage", "AgentMessage"):
                text = " ".join(c.get("text", "") for c in item.get("content") or [] if isinstance(c, dict))
                self.message(session, ts, "prompt" if item_type == "UserMessage" else "say", text, "item_completed")
            elif item_type == "CommandExecution":
                command = item.get("command")
                text = command[-1] if isinstance(command, list) and command else str(command or "")
                failed = item.get("status") == "failed" or item.get("exit_code") not in (None, 0)
                self.add(session, ts, "run", text, f"{text} {item.get('cwd', '')}", failed)
            elif item_type == "FileChange":
                paths = list((item.get("changes") or {}).keys())
                names = ", ".join(Path(p).name for p in paths[:4]) + (f" (+{len(paths) - 4})" if len(paths) > 4 else "")
                self.add(session, ts, "edit", f"zmienia: {names}", " ".join(paths))
            elif item_type == "McpToolCall":
                arguments = json.dumps(item.get("arguments") or {}, ensure_ascii=False)
                self.add(session, ts, "tool", f"{item.get('server', '')}/{item.get('tool', '')}", arguments)
            elif item_type == "Extension":
                self.add(session, ts, "tool", f"{item.get('kind', 'rozszerzenie')}: {item.get('query', '')}")

    def claude_line(self, session, raw):
        obj = json.loads(raw)
        kind = obj.get("type")
        if kind == "custom-title":
            session.title = obj.get("customTitle") or session.title
            return
        if kind not in ("user", "assistant"):
            return
        ts = parse_ts(obj.get("timestamp"))
        if "cwd" in obj:
            session.context = self.inside(obj["cwd"])
        message = obj.get("message") or {}
        content = message.get("content")
        if kind == "user":
            if obj.get("isMeta"):
                return
            session.started = True
            session.working = session.context
            texts = [content] if isinstance(content, str) else \
                [c.get("text", "") for c in content or [] if isinstance(c, dict) and c.get("type") == "text"]
            for text in texts:
                if text.strip() and not text.lstrip().startswith("<"):
                    self.message(session, ts, "prompt", text, "claude")
            return
        for item in content or []:
            if not isinstance(item, dict):
                continue
            if item.get("type") == "text":
                self.add(session, ts, "say", item.get("text", ""), item.get("text", ""))
            elif item.get("type") == "tool_use":
                name = item.get("name", "")
                data = item.get("input") or {}
                relevance = json.dumps(data, ensure_ascii=False)
                if name in ("Bash", "PowerShell"):
                    self.add(session, ts, "run", data.get("description") or data.get("command", ""), relevance)
                elif name in ("Edit", "Write", "NotebookEdit"):
                    self.add(session, ts, "edit", f"zmienia: {Path(str(data.get('file_path', ''))).name}", relevance)
                elif name == "Read":
                    self.add(session, ts, "tool", f"czyta: {Path(str(data.get('file_path', ''))).name}", relevance)
                else:
                    name = name.replace("mcp__", "").replace("__", "/")
                    label = data.get("description") or data.get("pattern") or data.get("skill") or ""
                    self.add(session, ts, "tool", f"{name}: {label}" if label else name, relevance)
        session.started = message.get("stop_reason") not in ("end_turn", "stop_sequence", "max_tokens")
        session.working = session.context and session.started

    def summary(self, now):
        result = {}
        for source, idle_after in (("CODEX", 2 * 3600), ("CLAUDE", 600)):
            linked = [s for s in self.sessions.values() if s.source == source and s.linked and not s.skip]
            if not linked:
                result[source] = {"status": "none", "sessions": 0}
                continue
            working = [s for s in linked if s.context and s.working and 0 <= now - s.last_ts < idle_after]
            session = max(working or linked, key=lambda s:s.last_ts)
            last = session.events[-1] if session.events else {}
            result[source] = {"status": "working" if working else "idle", "title": session.title,
                "last_ts": session.last_ts, "last_text": last.get("text", ""), "last_kind": last.get("kind", ""),
                "sessions": len(linked), "inferred": True}
        return result

    def timeline(self, limit=120):
        events = []
        for session in self.sessions.values():
            if session.linked and not session.skip:
                events.extend(dict(e, title=session.title) for e in session.events)
        return heapq.nlargest(limit, events, key=lambda e: e["ts"] or 0)


# --- serwer ------------------------------------------------------------------

class App:
    def __init__(self, root):
        self.root = Path(root)
        self.lock = threading.Lock()
        self.agents = AgentWatcher(root)
        self.store = FileStore(root, open_shared)
        self.verifier = Verifier(root)
        self.cache = self.last_good = None
        self.cache_at = 0.0
        self.last_poll = time.monotonic()
        self.index = None
        self.index_at = self.files_at = 0.0
        self.files = []

    def state(self):
        with self.lock:
            mono, now = time.monotonic(), time.time()
            if self.cache and mono - self.cache_at < 0.8:
                return self.cache
            errors = []
            try:
                # Known files are checked by metadata; new/deleted paths reconciled every 10s.
                changed = self.index is None or any(signature(path) != sig for path, sig in self.index)
                if changed or mono - self.index_at >= 10:
                    self.index, self.index_at = inventory(self.root), mono
                proofs = self.verifier.get(self.index)
                data = collect_project(self.root, self.store, proofs)
                if proofs.get("error"):
                    errors.append("Kontrola dowodów: " + proofs["error"])
                if proofs.get("origin") and not proofs["origin"].get("valid"):
                    errors.append("Niepotwierdzony origin: " + "; ".join(proofs["origin"].get("errors", [])))
                data["checking"] = bool(proofs.get("pending"))
                data["checked_at"] = self.verifier.checked_at if not proofs.get("pending") else None
            except Exception as exc:
                data = {"ok": False, "error": str(exc)}
            errors.extend(data.get("read_errors", []))
            if data.get("ok"):
                data["observed_at"] = now
                self.last_good = copy.deepcopy(data)
            elif self.last_good:
                error = data.get("error", "Błąd odczytu")
                data = copy.deepcopy(self.last_good)
                data["stale"] = True
                errors.append("Dane nieaktualne: " + error)
            try:
                self.agents.poll(now)
                agents, events = self.agents.summary(now), self.agents.timeline()
                errors.extend(self.agents.errors)
            except Exception as exc:
                agents, events = {}, []
                errors.append(f"Sesje agentów: {type(exc).__name__}: {exc}")
            try:
                if mono - self.files_at >= 30 or not self.files_at:
                    self.files = recent_files(self.root)
                    self.files_at = mono
            except Exception as exc:
                errors.append("Pliki projektu: " + str(exc))
            data.update(agents=agents, timeline=sorted(events + self.files, key=lambda e:e["ts"] or 0, reverse=True)[:150],
                        errors=errors, now=now)
            self.cache, self.cache_at = data, mono
            return data


def make_handler(app, port):
    allowed_hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            if self.headers.get("Host") not in allowed_hosts:
                self.send_error(403)
                return
            try:
                path = self.path.split("?", 1)[0]
                status = 200
                try:
                    if path == "/":
                        body, content_type = (HERE / "panel.html").read_bytes(), "text/html; charset=utf-8"
                    elif path == "/api/state":
                        app.last_poll = time.monotonic()
                        body = json.dumps(app.state(), ensure_ascii=False).encode("utf-8")
                        content_type = "application/json; charset=utf-8"
                    else:
                        self.send_error(404)
                        return
                except Exception:
                    status = 500
                    body = json.dumps({"ok": False, "error": "Błąd odczytu panelu; ponowię połączenie"}, ensure_ascii=False).encode("utf-8")
                    content_type = "application/json; charset=utf-8"
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                pass  # The browser may cancel an obsolete poll or close the tab.

    return Handler


def show_error(message):
    try:
        import tkinter
        from tkinter import messagebox
        window = tkinter.Tk()
        window.withdraw()
        messagebox.showerror("Panel projektu", message, parent=window)
        window.destroy()
    except Exception:
        print(message, file=sys.stderr)


def ask_folder():
    import tkinter
    from tkinter import filedialog
    window = tkinter.Tk()
    window.withdraw()
    window.attributes("-topmost", True)
    start = PROJECTS_ROOT if PROJECTS_ROOT.exists() else Path.home()
    chosen = filedialog.askdirectory(parent=window, initialdir=str(start), mustexist=True,
                                     title="Wybierz folder projektu Narrative V2")
    window.destroy()
    return Path(chosen) if chosen else None


def project_problem(path):
    try:
        text = read_text(path / "meta.md")
        if text is None:
            return f"W folderze nie ma meta.md:\n{path}"
        meta = parse_meta(text)[0]
        validate_meta(meta)
    except (OSError, ValueError) as exc:
        return str(exc)
    return None


def open_browser(url):
    if EDGE.exists():
        try:
            subprocess.Popen([str(EDGE), f"--app={url}", "--window-size=1360,960"], close_fds=True)
            return
        except OSError:
            pass
    if not webbrowser.open(url):
        raise RuntimeError("Nie można otworzyć przeglądarki. Panel: " + url)


def main():
    parser = argparse.ArgumentParser(description="Panel na żywo dla projektu Narrative V2 (tylko odczyt).")
    parser.add_argument("project", nargs="?", help="folder projektu; bez argumentu otwiera okno wyboru")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument("--dump", action="store_true", help="wypisz stan jako JSON i zakończ")
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        raise ValueError("Port musi należeć do zakresu 0–65535")

    root = Path(args.project.strip('"')) if args.project else ask_folder()
    while root is not None:
        problem = project_problem(root)
        if problem is None:
            break
        if args.project or args.dump:
            show_error(problem)
            return 2
        show_error(problem)
        root = ask_folder()
    if root is None:
        return 0
    root = root.resolve()
    app = App(root)

    if args.dump:
        if sys.stdout is None:
            raise RuntimeError("Tryb --dump uruchom przez python.exe w terminalu")
        sys.stdout.reconfigure(encoding="utf-8")
        print(json.dumps(app.state(), ensure_ascii=False, indent=1))
        return 0

    server = ThreadingHTTPServer(("127.0.0.1", args.port), None)
    port = server.server_address[1]
    server.RequestHandlerClass = make_handler(app, port)
    url = f"http://127.0.0.1:{port}/"

    def watchdog():
        previous = time.monotonic()
        while True:
            time.sleep(10)
            now = time.monotonic()
            if now - previous > 30:
                app.last_poll = now  # Wake from sleep: give browser time to reconnect.
            previous = now
            if now - app.last_poll > IDLE_EXIT_SECONDS:
                server.shutdown()
                return

    threading.Thread(target=watchdog, daemon=True).start()
    print(f"Panel: {url}  ({root})")
    if not args.no_browser:
        try:
            open_browser(url)
        except Exception:
            server.server_close()
            raise
    try:
        server.serve_forever()
    finally:
        server.server_close()
    return 0



def validate_meta(meta):
    if meta.get("WORKFLOW_REVISION") != V2_REVISION:
        raise ReadError("Panel obsługuje tylko Narrative V2; nie zmieniaj rewizji istniejącego projektu")
    stage = meta.get("CURRENT_STAGE")
    if stage not in STAGE_KEYS + ["BLOCKED"]:
        raise ReadError("Nieprawidłowy CURRENT_STAGE")
    if stage == "BLOCKED" and meta.get("BLOCKED_FROM_STAGE") not in STAGE_KEYS:
        raise ReadError("Brak poprawnego BLOCKED_FROM_STAGE")

def output_verdict(root, receipt, run_dir, outputs):
    paths = []
    if receipt and receipt.get("output_relative"):
        paths = [safe_relative(root, receipt["output_relative"])]
    elif len(outputs) == 1:
        paths = [run_dir / outputs[0]]
    if not paths:
        return None
    text = read_text(paths[0]) or ""
    matches = re.findall(r"(?m)^VERDICT:\s*(PASS|FAIL)\s*$", text)
    return matches[0] if len(matches) == 1 else None

def current_source_runs(ctx, all_runs):
    files, _ = active_sources(ctx.root)
    pdfs = {n.lower() for n in files if n.lower().endswith(".pdf")}
    sources = {("sources/" + n).lower() for n in files if not (n.lower().endswith("--text.md") and n[:-9].lower() + ".pdf" in pdfs)}
    grouped = {key: [] for key in sources}
    for run in all_runs:
        rel = (run.get("pdf_relative") or run.get("source_relative") or "").replace("\\", "/").lower()
        if rel in grouped and run.get("source_current"):
            grouped[rel].append(run)
    # Current publication may identify the authoritative run among historical alternatives.
    publication = None
    if ctx.proofs.get("publication", {}).get("valid"):
        relative = ctx.meta.get("K1_PUBLISH_RECEIPT_PATH")
        if relative:
            publication = read_json(safe_relative(ctx.root, relative))
    preferred = {x.get("run_id") for x in (publication or {}).get("source_lineage", [])}
    runs, problems = [], []
    for source, candidates in grouped.items():
        chosen = [r for r in candidates if r.get("run_id") in preferred]
        if len(chosen) == 1:
            runs.extend(chosen)
        elif len(candidates) == 1:
            runs.extend(candidates)
        else:
            problems.append(Path(source).name + (": kilka wersji runu" if candidates else ": brak aktualnego runu"))
    return runs, bool(sources) and not problems, "; ".join(problems) or "mapowanie źródeł zgodne"

def collect_project(root, store=None, proofs=None):
    store = store or FileStore(root, open_shared)
    previous = getattr(_io, "store", None), getattr(_io, "proofs", None)
    _io.store, _io.proofs = store, proofs or {}
    try:
        for attempt in range(2):
            store.begin()
            try:
                data = _collect_project(root)
            except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
                return {"ok": False, "error": str(exc)}
            if store.stable():
                return data
        return {"ok": False, "error": "Pliki zmieniają się podczas odczytu; czekam na spójny zapis"}
    finally:
        _io.store, _io.proofs = previous


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        show_error("Nie udało się uruchomić panelu: " + str(exc))
        sys.exit(1)
