import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_k1_lite_v2 import build_k1_source, make_result, write_json
import k1_lite_v2_core as core
from next_work import next_work
from batch_import import import_batch
import next_work as queue_module


class EfficiencyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source, self.pdf, _ = build_k1_source(self.root)
        self.run_dir = self.root / '_work/K1/k1-lite-v2/run'

    def plan(self, limit=2):
        core.initialize_run(isolation_root=self.root, source_path=self.source,
            expected_source_sha=core.sha256_file(self.source), pdf_path=self.pdf,
            expected_pdf_sha=core.sha256_file(self.pdf), run_dir=self.run_dir,
            k0_path=None, expected_k0_sha=None, target_min=1000, target_max=4000,
            candidate_limit=limit)
        return core.load_run(self.run_dir, self.root)

    def make_files(self, run, chunks):
        result = []
        for i, chunk in enumerate(chunks):
            p = self.run_dir / 'incoming' / f'{i}.json'
            write_json(p, make_result(run, chunk, candidates=[]))
            result.append(p)
        return result

    def test_batch_one_source_load_and_queue_complete(self):
        run, chunks, _ = self.plan()
        self.assertEqual(next_work(isolation_root=self.root, run_dir=self.run_dir)['next']['continuation_no'], 0)
        files = self.make_files(run, chunks)
        with patch('batch_import.load_run', wraps=core.load_run) as load:
            report = import_batch(isolation_root=self.root, run_dir=self.run_dir,
                                  result_paths=files, expected_ledger_sha='CREATE_NEW')
            self.assertEqual(load.call_count, 1)
        self.assertEqual(len(report['imported_results']), len(chunks))
        pending = next_work(isolation_root=self.root, run_dir=self.run_dir)
        self.assertIsNone(pending['next'])
        self.assertEqual(pending['status'], 'ANALYSIS_COMPLETE_REVIEW_REQUIRED')
        core.validate_run(isolation_root=self.root, run_dir=self.run_dir)

    def test_bad_last_result_has_no_partial_import(self):
        run, chunks, _ = self.plan()
        files = self.make_files(run, chunks)
        bad = json.loads(files[-1].read_text()); bad['chunk_sha256'] = '0'*64
        write_json(files[-1], bad)
        with self.assertRaises(core.K1LiteV2Error):
            import_batch(isolation_root=self.root, run_dir=self.run_dir, result_paths=files, expected_ledger_sha='CREATE_NEW')
        self.assertFalse((self.run_dir/'ledger.jsonl').exists())
        self.assertEqual(list((self.run_dir/'results').iterdir()), [])

    def test_wrong_ledger_hash_rolls_back_receipts(self):
        run, chunks, _ = self.plan()
        with self.assertRaises(core.K1LiteV2Error):
            import_batch(isolation_root=self.root, run_dir=self.run_dir,
                         result_paths=self.make_files(run, chunks), expected_ledger_sha='0'*64)
        self.assertEqual(list((self.run_dir/'results').iterdir()), [])

    def test_changed_source_blocks_queue(self):
        self.plan()
        self.source.write_text(self.source.read_text()+'changed')
        with self.assertRaisesRegex(core.K1LiteV2Error, 'STALE'):
            next_work(isolation_root=self.root, run_dir=self.run_dir)

    def test_changed_packet_blocks_queue(self):
        _, chunks, _ = self.plan()
        (self.run_dir/'worker-input'/f"{chunks[0]['chunk_id']}.md").write_text('tampered')
        with self.assertRaises(core.K1LiteV2Error):
            next_work(isolation_root=self.root, run_dir=self.run_dir)

    def test_four_candidates_and_continuation_context(self):
        run, chunks, doc = self.plan(4)
        chunk = next(c for c in chunks if 'P0003' in c['pages'])
        quotes = ['Appendix three is content and must not be skipped.',
                  'Appendix three is content and must not',
                  'three is content and must not be skipped.']
        candidates = [{'local_id': chr(65+i), 'page':'P0003', 'quote':q,
                       'claim':q, 'category':'OPEN_DISCOVERY', 'speaker_mode':'AUTHOR_CLAIM', 'film_value':1, 'risk':1, 'facts':[]} for i,q in enumerate(quotes)]
        value = make_result(run,chunk,candidates=candidates,more=True)
        p=self.run_dir/'incoming'/'overflow.json';write_json(p,value)
        result=core.import_worker_result(isolation_root=self.root,run_dir=self.run_dir,
                    result_path=p,expected_ledger_sha='CREATE_NEW')
        # Finish earlier chunks so the continuation is next.
        earlier=[c for c in chunks if c['chunk_id'] < chunk['chunk_id']]
        if earlier:
            import_batch(isolation_root=self.root,run_dir=self.run_dir,
                result_paths=self.make_files(run,earlier),expected_ledger_sha=result['ledger_sha256'])
        pending=next_work(isolation_root=self.root,run_dir=self.run_dir)['next']
        self.assertEqual(pending['chunk_id'],chunk['chunk_id'])
        self.assertEqual(pending['continuation_no'],1)
        self.assertEqual(len(pending['previous_candidates']),3)
        core.validate_run(isolation_root=self.root,run_dir=self.run_dir)
        packet=(self.run_dir/'worker-input'/f"{chunk['chunk_id']}.md").read_text('utf-8')
        self.assertIn('Maksymalnie 4',packet)

    def test_invalid_limit(self):
        with self.assertRaisesRegex(core.K1LiteV2Error,'CANDIDATE_LIMIT_INVALID'):
            self.plan(3)

    def test_changed_candidate_limit_is_rejected(self):
        run, _, _ = self.plan(4)
        run['candidate_limit'] = 8
        write_json(self.run_dir/'run.json', run)
        with self.assertRaisesRegex(core.K1LiteV2Error, 'RUN_ANALYSIS_POLICY_STALE'):
            core.load_run(self.run_dir, self.root)

    def test_concurrent_ledger_change_does_not_return_mixed_queue(self):
        self.plan()
        original = core.validate_ledger_semantics
        def changed_during_validation(*args, **kwargs):
            original(*args, **kwargs)
            (self.run_dir/'ledger.jsonl').write_bytes(b'{}\n')
        with patch.object(queue_module, 'validate_ledger_semantics', side_effect=changed_during_validation):
            with self.assertRaisesRegex(core.K1LiteV2Error, 'NEXT_WORK_LEDGER_CHANGED'):
                next_work(isolation_root=self.root, run_dir=self.run_dir)

    def test_batch_output_redirect_outside_project_is_blocked(self):
        run, chunks, _ = self.plan()
        files = self.make_files(run, chunks)
        outside_temp = tempfile.TemporaryDirectory()
        self.addCleanup(outside_temp.cleanup)
        outside = Path(outside_temp.name).resolve()
        link = self.run_dir/'results'
        link.rmdir()  # Empty directory of this newly created fixture only.
        if os.name == 'nt':
            command = "New-Item -ItemType Junction -Path '" + str(link).replace("'", "''") + "' -Target '" + str(outside).replace("'", "''") + "' | Out-Null"
            subprocess.run(['pwsh', '-NoProfile', '-Command', command], check=True, capture_output=True)
            self.addCleanup(os.rmdir, link)
        else:
            link.symlink_to(outside, target_is_directory=True)
            self.addCleanup(link.unlink)
        with self.assertRaisesRegex(core.K1LiteV2Error, 'PATH_OUTSIDE_ISOLATION_ROOT|WORK_REPARSE_POINT_BLOCKED'):
            import_batch(isolation_root=self.root, run_dir=self.run_dir, result_paths=files,
                         expected_ledger_sha='CREATE_NEW')
        with self.assertRaisesRegex(core.K1LiteV2Error, 'PATH_OUTSIDE_ISOLATION_ROOT'):
            core.import_worker_result(isolation_root=self.root, run_dir=self.run_dir,
                                      result_path=files[0], expected_ledger_sha='CREATE_NEW')
        self.assertEqual(list(outside.iterdir()), [])
        self.assertFalse((self.run_dir/'ledger.jsonl').exists())

    def test_partial_file_write_is_removed(self):
        target = self.root / 'failed-receipt.json'
        original_open = Path.open
        @contextmanager
        def failing_open(path, *args, **kwargs):
            with original_open(path, *args, **kwargs) as handle:
                class FailedWriter:
                    def write(self, payload):
                        handle.write(payload[:2])
                        raise OSError('disk full')
                yield FailedWriter()
        with patch.object(Path, 'open', failing_open):
            with self.assertRaisesRegex(OSError, 'disk full'):
                core.write_new(target, b'{"receipt":true}')
        self.assertFalse(target.exists())


if __name__ == '__main__':
    unittest.main()
