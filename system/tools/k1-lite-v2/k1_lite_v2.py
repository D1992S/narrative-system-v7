#!/usr/bin/env python3
"""Command-line entrypoint for the isolated K1-Lite V2 analysis layer."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from next_work import next_work
from batch_import import import_batch

from k1_lite_v2_core import (
    K1LiteV2Error,
    add_decisions,
    add_editorial_review_receipt,
    add_visual_receipt,
    build_views,
    compare_text_twins,
    import_worker_result,
    initialize_run,
    inspect_pdf_layout,
    validate_run,
    verify_quote_batch,
)


def add_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--isolation-root", required=True, type=Path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="K1-Lite V2 isolated analysis tooling")
    subparsers = parser.add_subparsers(dest="command", required=True)

    plan = subparsers.add_parser("plan", help="Create a section-aware, immutable analysis run")
    add_common(plan)
    plan.add_argument("--source", required=True, type=Path)
    plan.add_argument("--expected-source-sha256", required=True)
    plan.add_argument("--pdf", type=Path)
    plan.add_argument("--expected-pdf-sha256")
    plan.add_argument("--run-dir", required=True, type=Path)
    plan.add_argument("--k0", type=Path)
    plan.add_argument("--expected-k0-sha256")
    plan.add_argument("--candidate-limit", type=int, choices=[2,4,8], default=2)
    plan.add_argument("--target-min", type=int, default=12000)
    plan.add_argument("--target-max", type=int, default=18000)

    next_parser = subparsers.add_parser("next-work", help="Read validated pending work without changing the run")
    add_common(next_parser)
    next_parser.add_argument("--run-dir", required=True, type=Path)

    batch = subparsers.add_parser("import-batch")
    add_common(batch)
    batch.add_argument("--run-dir", required=True, type=Path)
    batch.add_argument("--result", required=True, action="append", type=Path)
    batch.add_argument("--expected-ledger-sha256", required=True)

    import_result = subparsers.add_parser("import-result", help="Validate and append one worker result")
    add_common(import_result)
    import_result.add_argument("--run-dir", required=True, type=Path)
    import_result.add_argument("--result", required=True, type=Path)
    import_result.add_argument("--expected-ledger-sha256", required=True)

    decisions = subparsers.add_parser("add-decisions", help="Append editorial decisions as immutable events")
    add_common(decisions)
    decisions.add_argument("--run-dir", required=True, type=Path)
    decisions.add_argument("--decisions", required=True, type=Path)
    decisions.add_argument("--expected-ledger-sha256", required=True)

    visual = subparsers.add_parser("add-visual", help="Append a hash-bound full-page and crop receipt")
    add_common(visual)
    visual.add_argument("--run-dir", required=True, type=Path)
    visual.add_argument("--receipt", required=True, type=Path)
    visual.add_argument("--expected-ledger-sha256", required=True)

    review = subparsers.add_parser("add-review", help="Append Dawid's hash-bound editorial review receipt")
    add_common(review)
    review.add_argument("--run-dir", required=True, type=Path)
    review.add_argument("--receipt", required=True, type=Path)
    review.add_argument("--expected-ledger-sha256", required=True)

    views = subparsers.add_parser("build-views", help="Generate coverage, candidate, conflict and staging views")
    add_common(views)
    views.add_argument("--run-dir", required=True, type=Path)
    views.add_argument("--output-dir", required=True, type=Path)

    validate = subparsers.add_parser("validate-run", help="Validate current source, packets and ledger")
    add_common(validate)
    validate.add_argument("--run-dir", required=True, type=Path)

    quote_qa = subparsers.add_parser("verify-batch", help="Re-resolve all active quotes in one source pass")
    add_common(quote_qa)
    quote_qa.add_argument("--run-dir", required=True, type=Path)
    quote_qa.add_argument("--output", required=True, type=Path)

    layout = subparsers.add_parser("inspect-layout", help="Create a heuristic native-PDF layout review queue")
    add_common(layout)
    layout.add_argument("--run-dir", required=True, type=Path)
    layout.add_argument("--output", required=True, type=Path)

    twins = subparsers.add_parser("compare-text-twins", help="Compare page-anchored transcripts of one PDF")
    add_common(twins)
    twins.add_argument("--first", required=True, type=Path)
    twins.add_argument("--first-sha256", required=True)
    twins.add_argument("--second", required=True, type=Path)
    twins.add_argument("--second-sha256", required=True)
    twins.add_argument("--pdf-sha256", required=True)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "plan":
            result = initialize_run(
                isolation_root=args.isolation_root,
                source_path=args.source,
                expected_source_sha=args.expected_source_sha256,
                pdf_path=args.pdf,
                expected_pdf_sha=args.expected_pdf_sha256,
                run_dir=args.run_dir,
                k0_path=args.k0,
                expected_k0_sha=args.expected_k0_sha256,
                candidate_limit=args.candidate_limit,
                target_min=args.target_min,
                target_max=args.target_max,
            )
        elif args.command == "import-batch":
            result = import_batch(isolation_root=args.isolation_root, run_dir=args.run_dir, result_paths=args.result, expected_ledger_sha=args.expected_ledger_sha256)
        elif args.command == "next-work":
            result = next_work(isolation_root=args.isolation_root, run_dir=args.run_dir)
        elif args.command == "import-result":
            result = import_worker_result(
                isolation_root=args.isolation_root,
                run_dir=args.run_dir,
                result_path=args.result,
                expected_ledger_sha=args.expected_ledger_sha256,
            )
        elif args.command == "add-decisions":
            result = add_decisions(
                isolation_root=args.isolation_root,
                run_dir=args.run_dir,
                decision_path=args.decisions,
                expected_ledger_sha=args.expected_ledger_sha256,
            )
        elif args.command == "add-visual":
            result = add_visual_receipt(
                isolation_root=args.isolation_root,
                run_dir=args.run_dir,
                receipt_path=args.receipt,
                expected_ledger_sha=args.expected_ledger_sha256,
            )
        elif args.command == "add-review":
            result = add_editorial_review_receipt(
                isolation_root=args.isolation_root,
                run_dir=args.run_dir,
                receipt_path=args.receipt,
                expected_ledger_sha=args.expected_ledger_sha256,
            )
        elif args.command == "build-views":
            result = build_views(
                isolation_root=args.isolation_root,
                run_dir=args.run_dir,
                output_dir=args.output_dir,
            )
        elif args.command == "validate-run":
            result = validate_run(isolation_root=args.isolation_root, run_dir=args.run_dir)
        elif args.command == "verify-batch":
            result = verify_quote_batch(
                isolation_root=args.isolation_root,
                run_dir=args.run_dir,
                output_path=args.output,
            )
        elif args.command == "inspect-layout":
            result = inspect_pdf_layout(
                isolation_root=args.isolation_root,
                run_dir=args.run_dir,
                output_path=args.output,
            )
        else:
            result = compare_text_twins(
                isolation_root=args.isolation_root,
                first_path=args.first,
                first_sha=args.first_sha256,
                second_path=args.second,
                second_sha=args.second_sha256,
                pdf_sha=args.pdf_sha256,
            )
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (K1LiteV2Error, OSError, ValueError, KeyError) as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
