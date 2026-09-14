"""One validated source snapshot per batch; recoverable receipt publication."""
import json
import uuid
from pathlib import Path
from k1_lite_v2_core import (K1LiteV2Error, ensure_within, ensure_run_location, require_file,
    load_run, read_jsonl, validate_ledger_semantics, validate_worker_result, sha256_bytes,
    sha256_file, verify_file_sha, append_ledger, utc_now, LEDGER_EVENT_SCHEMA)
from work_io import safe, atomic_new, json_bytes


class Snapshot:
    def __init__(self, root: Path, run_path: Path):
        self.root = safe(root, root)
        self.path = ensure_run_location(safe(run_path, self.root), self.root)
        self.guards = {}
        for name in ('run.json', 'chunks.jsonl'):
            path = safe(self.path/name, self.root)
            self.guards[path] = sha256_file(path)
        self.run, self.chunks, self.document = load_run(self.path, self.root)
        self.ledger_path = safe(self.path/'ledger.jsonl', self.root)
        self.ledger_sha = sha256_file(self.ledger_path) if self.ledger_path.exists() else 'CREATE_NEW'
        self.ledger = read_jsonl(self.ledger_path)
        validate_ledger_semantics(self.run, self.chunks, self.document, self.ledger, self.root, self.path)
        self.chunk_map = {c['chunk_id']: c for c in self.chunks}
        for c in self.chunks:
            p = require_file(self.path/'worker-input'/(c['chunk_id']+'.md'), self.root)
            verify_file_sha(p, c['packet_sha256'], 'PACKET')
            self.guards[p] = c['packet_sha256']
        for key in ('source', 'pdf', 'k0'):
            if self.run.get(key+'_relative'):
                self.guards[require_file(self.root/self.run[key+'_relative'], self.root)] = self.run[key+'_sha256']
        self.check()

    def check(self):
        for path, digest in self.guards.items():
            verify_file_sha(require_file(path, self.root), digest, 'BATCH_INPUT')
        actual = sha256_file(self.ledger_path) if self.ledger_path.exists() else 'CREATE_NEW'
        if actual != self.ledger_sha:
            raise K1LiteV2Error('LEDGER_CHANGED_DURING_BATCH')


def stage(snapshot, result_paths, *, keep_valid=False):
    if not result_paths or len(result_paths) > 100:
        raise K1LiteV2Error('BATCH_SIZE_INVALID')
    additions, receipts, summaries, errors, valid_inputs = [], [], [], [], []
    seen = set()
    for path in result_paths:
        try:
            data = require_file(path, snapshot.root).read_bytes()
            result = json.loads(data)
            if not isinstance(result, dict) or result.get('chunk_id') not in snapshot.chunk_map:
                raise K1LiteV2Error('WORKER_CHUNK_UNKNOWN')
            chunk_id = result['chunk_id']
            records, event = validate_worker_result(result=result, run=snapshot.run,
                chunk=snapshot.chunk_map[chunk_id], document=snapshot.document,
                ledger=snapshot.ledger+additions, isolation_root=snapshot.root)
            digest = sha256_bytes(data)
            receipt = safe(snapshot.path/'results'/f"{chunk_id}-{event['continuation_no']:02d}-{digest[:12]}.json", snapshot.root)
            if receipt in seen:
                raise K1LiteV2Error('WORKER_RESULT_ALREADY_IMPORTED')
            seen.add(receipt)
            additions.extend(records)
            additions.append({'schema':LEDGER_EVENT_SCHEMA, 'event_type':'result_receipt',
                'event_id':uuid.uuid4().hex.upper(), 'created_at':utc_now(), 'run_id':snapshot.run['run_id'],
                'chunk_id':chunk_id, 'continuation_no':event['continuation_no'],
                'result_sha256':digest, 'stored_relative':receipt.relative_to(snapshot.root).as_posix()})
            receipts.append((receipt,data))
            summaries.append({'chunk_id':chunk_id,'continuation_no':event['continuation_no']})
            valid_inputs.append({'path':str(path),'sha256':digest})
        except (K1LiteV2Error, ValueError, UnicodeError, OSError, TypeError, KeyError) as exc:
            if not keep_valid:
                if isinstance(exc, (K1LiteV2Error,OSError)): raise
                raise K1LiteV2Error('BATCH_RESULT_INVALID') from exc
            errors.append({'path':str(path), 'error':str(exc)[:400]})
    snapshot.check()
    return {'additions':additions, 'receipts':receipts, 'summaries':summaries, 'errors':errors,'valid_inputs':valid_inputs}


def commit(snapshot, staged, expected_ledger_sha):
    if expected_ledger_sha.upper() != snapshot.ledger_sha:
        raise K1LiteV2Error('LEDGER_SHA_MISMATCH')
    snapshot.check()
    manifest = {'schema':'K1_BATCH_TRANSACTION_V1','run_id':snapshot.run['run_id'],
        'previous_ledger_sha':snapshot.ledger_sha,
        'receipts':[{'path':p.relative_to(snapshot.root).as_posix(),'sha256':sha256_bytes(b)} for p,b in staged['receipts']]}
    transaction = safe(snapshot.path/'batch-transactions'/(sha256_bytes(json_bytes(manifest))+'.json'),snapshot.root)
    # A different chunk may have committed since an interrupted publication.
    # Reuse only receipts claimed by a hash-verified transaction in this run.
    owned = set()
    transaction_dir = safe(snapshot.path/'batch-transactions', snapshot.root)
    # Ordinary imports do not need to rescan the whole transaction history.
    existing_receipts = [(p,b) for p,b in staged['receipts'] if p.exists()]
    for previous in transaction_dir.glob('*.json') if existing_receipts else ():
        payload = require_file(safe(previous, snapshot.root), snapshot.root).read_bytes()
        if previous.stem != sha256_bytes(payload):
            raise K1LiteV2Error('BATCH_TRANSACTION_TAMPERED')
        try: prior = json.loads(payload)
        except (ValueError,UnicodeError) as exc:
            raise K1LiteV2Error('BATCH_TRANSACTION_INVALID') from exc
        if not isinstance(prior,dict) or prior.get('schema') != 'K1_BATCH_TRANSACTION_V1' or prior.get('run_id') != snapshot.run['run_id']:
            raise K1LiteV2Error('BATCH_TRANSACTION_INVALID')
        receipts=prior.get('receipts')
        if not isinstance(receipts,list) or any(not isinstance(r,dict) or
            not isinstance(r.get('path'),str) or not isinstance(r.get('sha256'),str) for r in receipts):
            raise K1LiteV2Error('BATCH_TRANSACTION_INVALID')
        owned.update((r['path'], r['sha256']) for r in receipts)
    for p,b in existing_receipts:
        identity = (p.relative_to(snapshot.root).as_posix(), sha256_bytes(b))
        if p.exists() and (identity not in owned or p.read_bytes()!=b):
            raise K1LiteV2Error('WORKER_RESULT_ALREADY_IMPORTED')
    atomic_new(transaction,json_bytes(manifest))
    created=[]
    try:
        for p,b in staged['receipts']:
            if atomic_new(p,b): created.append(p)
        snapshot.check()
        digest=append_ledger(snapshot.ledger_path,staged['additions'],snapshot.ledger_sha)
    except Exception:
        # An error after atomic ledger replacement must not delete its receipts.
        try:
            current=sha256_file(snapshot.ledger_path) if snapshot.ledger_path.exists() else 'CREATE_NEW'
        except OSError:
            current=None
        if current==snapshot.ledger_sha:
            for p in created: p.unlink(missing_ok=True)
        raise
    snapshot.ledger += staged['additions']
    snapshot.ledger_sha = digest
    return {'schema':'K1_BATCH_IMPORT_V1','run_id':snapshot.run['run_id'],
        'imported_results':staged['summaries'],'ledger_sha256':digest,
        'events_appended':len(staged['additions'])}


def import_batch(*, isolation_root: Path, run_dir: Path, result_paths: list[Path], expected_ledger_sha: str):
    snapshot=Snapshot(isolation_root,run_dir)
    return commit(snapshot,stage(snapshot,result_paths),expected_ledger_sha)


def preview_batch(*, isolation_root: Path, run_dir: Path, result_paths: list[Path]):
    snapshot=Snapshot(isolation_root,run_dir)
    staged=stage(snapshot,result_paths,keep_valid=True)
    return {'schema':'K1_BATCH_PREVIEW_V1','ledger_sha256':snapshot.ledger_sha,
            'valid_results':staged['summaries'],
            'valid_inputs':staged['valid_inputs'],
            'errors':staged['errors'],'published':False}
