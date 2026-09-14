"""Read-only Ruff report; fail on likely runtime/syntax errors, retain all findings."""
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "artifacts"
OUTPUT.mkdir(exist_ok=True)
report = OUTPUT / "ruff.json"
result = subprocess.run([
    sys.executable, "-m", "ruff", "check", "system", "panel", ".github/scripts",
    "--no-cache", "--select", "E4,E7,E9,F,B", "--output-format", "json",
    "--output-file", str(report),
], cwd=ROOT, check=False)
if result.returncode not in (0, 1):
    sys.exit(result.returncode)
findings = json.loads(report.read_text(encoding="utf-8"))
blocking = [item for item in findings if (item.get("code") or "invalid-syntax").startswith(
    ("E9", "F63", "F7", "F82", "invalid-syntax"))]
print(f"Ruff: {len(findings)} findings, {len(blocking)} blocking; artifacts/ruff.json")

def escape(value):
    return str(value).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A").replace(",", "%2C").replace(":", "%3A")

if os.environ.get("GITHUB_ACTIONS") == "true":
    for item in (blocking + [x for x in findings if x not in blocking])[:20]:
        level = "error" if item in blocking else "warning"
        relative = Path(item["filename"]).relative_to(ROOT).as_posix()
        print(f"::{level} file={escape(relative)},line={item['location']['row']}::{escape(item['code'])}: {escape(item['message'])}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"### Python / Ruff\n\nFindings: **{len(findings)}**; blocking: **{len(blocking)}**. Full report: `ruff.json`.\n\n")
sys.exit(1 if blocking else 0)
