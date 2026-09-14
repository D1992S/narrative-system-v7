"""Read-only queue derived from validated source, packets and imported results."""
from pathlib import Path
from k1_lite_v2_core import (K1LiteV2Error, ensure_within, ensure_run_location, load_run, read_jsonl,
    require_file, verify_file_sha, validate_ledger_semantics, coverage_state, sha256_file)


def next_work(*, isolation_root: Path, run_dir: Path):
    root = ensure_within(isolation_root, isolation_root)
    run_path = ensure_run_location(run_dir, root)
    run, chunks, document = load_run(run_path, root)
    ledger_path = ensure_within(run_path / 'ledger.jsonl', root)
    ledger_sha = sha256_file(ledger_path) if ledger_path.exists() else 'CREATE_NEW'
    ledger = read_jsonl(ledger_path)
    validate_ledger_semantics(run, chunks, document, ledger, root, run_path)
    packets = {}
    for chunk in chunks:
        path = require_file(run_path / 'worker-input' / (chunk['chunk_id'] + '.md'), root)
        verify_file_sha(path, chunk['packet_sha256'], 'PACKET')
        packets[chunk['chunk_id']] = path
    coverage = coverage_state(chunks, ledger)
    pending = [c for c in coverage if not c['complete']]
    result = {'schema': 'K1_NEXT_WORK_V1', 'run_id': run['run_id'],
              'ledger_sha256': ledger_sha,
              'complete_chunks': len(chunks) - len(pending), 'total_chunks': len(chunks),
              'pending_chunks': len(pending), 'candidate_limit': run.get('candidate_limit', 2),
              'status': 'ANALYSIS_COMPLETE_REVIEW_REQUIRED' if not pending else 'WORK_AVAILABLE',
              'next': None}
    if pending:
        item = pending[0]
        prior = [{'candidate_id': e['candidate_id'], 'quote': e.get('quote'), 'page': e.get('page')}
                 for e in ledger if e.get('event_type') == 'candidate' and e.get('chunk_id') == item['chunk_id']]
        result['next'] = {'chunk_id': item['chunk_id'], 'continuation_no': item['continuations'],
                          'packet_relative': packets[item['chunk_id']].relative_to(root).as_posix(),
                          'previous_candidates': prior,
                          'instruction': 'Read the entire unchanged packet. Return further strong candidates without repeating previous candidates; retain source context and required schema.'}
    current_sha = sha256_file(ledger_path) if ledger_path.exists() else 'CREATE_NEW'
    if current_sha != ledger_sha:
        raise K1LiteV2Error('NEXT_WORK_LEDGER_CHANGED: retry NextWork')
    return result
