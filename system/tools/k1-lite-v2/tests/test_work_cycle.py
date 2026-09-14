import json
import os
import sys
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import k1_lite_v2_core as core
import batch_import
import work_cycle as work
from work_io import run_lock
from test_k1_lite_v2 import build_k1_source, make_result, write_json


class WorkCycleTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name).resolve()
        self.source,self.pdf,_=build_k1_source(self.root)
        self.run=self.root/'_work/K1/k1-lite-v2/run'
        core.initialize_run(isolation_root=self.root,source_path=self.source,
            expected_source_sha=core.sha256_file(self.source),pdf_path=self.pdf,
            expected_pdf_sha=core.sha256_file(self.pdf),run_dir=self.run,k0_path=None,
            expected_k0_sha=None,target_min=1000,target_max=4000)
        self.info,self.chunks,self.doc=core.load_run(self.run,self.root)

    def cycle(self,action,**kwargs):
        return work.cycle(action,self.root,self.run,**kwargs)

    def answer(self,job,*,compact=False,bad=False):
        folder,req=work.read_request(self.run,self.root,job['task_id'])
        chunk=next(c for c in self.chunks if c['chunk_id']==req['chunk_id'])
        data=make_result(self.info,chunk,candidates=[],continuation=req['continuation_no'])
        if bad: data['probe_answers']={}
        if compact:
            data={k:data[k] for k in ('status','more_strong_candidates','probe_answers','candidates')}
            data.update(schema=work.REPLY,task_id=job['task_id'])
        path=folder/('bad.json' if bad else 'reply.json')
        write_json(path,data)
        return path

    def test_prepare_reuses_one_task_and_full_packet(self):
        first=self.cycle('Prepare'); second=self.cycle('Prepare')
        self.assertEqual(first['task_id'],second['task_id'])
        self.assertEqual(second['status'],'WAITING_FOR_RESPONSE')
        self.assertFalse(second['new_model_call_required'])
        packet=(self.run/'worker-input'/f"{self.chunks[0]['chunk_id']}.md").read_text('utf-8')
        self.assertEqual(Path(first['input_path']).read_text('utf-8').split('## Treść\n\n',1)[1],
                         packet.split('## Treść\n\n',1)[1])
        self.assertEqual(len(list((self.run/'jobs').glob('*/request.json'))),1)

    def test_accept_and_duplicate_are_idempotent(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        result=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(result['status'],'IMPORTED')
        digest=core.sha256_file(self.run/'ledger.jsonl')
        again=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(again['status'],'ALREADY_IMPORTED')
        self.assertEqual(core.sha256_file(self.run/'ledger.jsonl'),digest)

    def test_compact_transport_has_unavailable_metrics(self):
        job=self.cycle('Prepare'); path=self.answer(job,compact=True)
        with patch('batch_import.load_run',wraps=core.load_run) as load:
            result=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(result['status'],'IMPORTED')
        self.assertEqual(load.call_count,1)
        records=core.read_jsonl(self.run/'ledger.jsonl')
        event=next(e for e in records if e['event_type']=='chunk_result')
        self.assertEqual(event['metrics']['measurement'],'UNAVAILABLE')

    def test_bad_reply_is_saved_and_prepare_does_not_redispatch(self):
        job=self.cycle('Prepare'); path=self.answer(job,bad=True)
        result=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(result['status'],'NEEDS_CORRECTION')
        path.unlink()
        self.assertEqual(self.cycle('Prepare')['status'],'NEEDS_CORRECTION')
        self.assertFalse((self.run/'ledger.jsonl').exists())

    def test_local_failure_recovers_saved_answer(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        with patch('batch_import.append_ledger',side_effect=OSError('disk unavailable')):
            result=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(result['status'],'RETRY_LOCAL'); path.unlink()
        self.assertEqual(self.cycle('Recover',task_id=job['task_id'])['status'],'IMPORTED')

    def test_crash_after_receipts_recovers_without_new_answer(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        with patch('batch_import.append_ledger',side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertTrue(list((self.run/'results').glob('*.json')))
        self.assertEqual(self.cycle('Recover',task_id=job['task_id'])['status'],'IMPORTED')

    def test_crash_after_publication_does_not_duplicate(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        real=work.atomic_new
        def fail_marker(p,data):
            if p.name=='accepted.json': raise KeyboardInterrupt
            return real(p,data)
        with patch.object(work,'atomic_new',side_effect=fail_marker):
            with self.assertRaises(KeyboardInterrupt):
                self.cycle('Accept',task_id=job['task_id'],response_path=path)
        digest=core.sha256_file(self.run/'ledger.jsonl')
        self.assertEqual(self.cycle('Recover',task_id=job['task_id'])['status'],'ALREADY_IMPORTED')
        self.assertEqual(core.sha256_file(self.run/'ledger.jsonl'),digest)

    def test_orphan_receipt_recovers_after_unrelated_import(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        with patch('batch_import.append_ledger',side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.cycle('Accept',task_id=job['task_id'],response_path=path)
        other=self.run/'incoming/other.json'
        write_json(other,make_result(self.info,self.chunks[-1],candidates=[]))
        core.import_worker_result(isolation_root=self.root,run_dir=self.run,
            result_path=other,expected_ledger_sha='CREATE_NEW')
        self.assertEqual(self.cycle('Recover',task_id=job['task_id'])['status'],'IMPORTED')
        core.validate_run(isolation_root=self.root,run_dir=self.run)

    def test_changed_source_preserves_response_and_blocks_import(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        self.source.write_bytes(self.source.read_bytes()+b'changed')
        result=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(result['status'],'STALE_OR_BLOCKED')
        self.assertTrue(result['response_preserved'])
        self.assertFalse((self.run/'ledger.jsonl').exists())

    def test_request_tamper_and_path_escape_are_rejected(self):
        job=self.cycle('Prepare')
        with self.assertRaises(core.K1LiteV2Error): self.cycle('Recover',task_id='../escape')
        p=self.run/'jobs'/job['task_id']/'request.json'
        data=json.loads(p.read_bytes()); data['candidate_limit']=8; write_json(p,data)
        with self.assertRaisesRegex(core.K1LiteV2Error,'TAMPERED'):
            self.cycle('Recover',task_id=job['task_id'])

    def test_unknown_delivery_does_not_dispatch_again(self):
        job=self.cycle('Prepare')
        result=self.cycle('Recover',task_id=job['task_id'])
        self.assertEqual(result['status'],'WAITING_FOR_RESPONSE')
        self.assertFalse(result['automatic_model_retry'])

    def test_lock_excludes_second_writer(self):
        with run_lock(self.run,self.root):
            with self.assertRaisesRegex(core.K1LiteV2Error,'WORK_CYCLE_BUSY'): self.cycle('Prepare')

    def test_complete_run_does_not_prepare_new_task(self):
        for _ in self.chunks:
            job=self.cycle('Prepare')
            self.cycle('Accept',task_id=job['task_id'],response_path=self.answer(job,compact=True))
        result=self.cycle('Prepare')
        self.assertEqual(result['status'],'ANALYSIS_COMPLETE_REVIEW_REQUIRED')
        core.validate_run(isolation_root=self.root,run_dir=self.run)

    def test_preview_retains_valid_results_without_publication(self):
        paths=[]
        for i,chunk in enumerate(self.chunks):
            value=make_result(self.info,chunk,candidates=[])
            if i==len(self.chunks)-1: value['chunk_sha256']='0'*64
            p=self.run/'incoming'/f'{i}.json'; write_json(p,value); paths.append(p)
        with patch('batch_import.load_run',wraps=core.load_run) as load:
            result=self.cycle('PreviewBatch',result_paths=paths)
        self.assertEqual(load.call_count,1)
        self.assertEqual(len(result['valid_results']),len(paths)-1)
        self.assertEqual(len(result['errors']),1)
        self.assertFalse((self.run/'ledger.jsonl').exists())

    def test_status_is_read_only(self):
        before={p.relative_to(self.run):p.read_bytes() for p in self.run.rglob('*') if p.is_file()}
        self.cycle('Status')
        after={p.relative_to(self.run):p.read_bytes() for p in self.run.rglob('*') if p.is_file()}
        self.assertEqual(before,after)

    def test_powershell_wrapper_prepare_accept_recover_status(self):
        (self.root/'.system-v7').mkdir()
        (self.root/'sources').mkdir(exist_ok=True)
        wrapper=Path(__file__).resolve().parents[1]/'Invoke-K1WorkCycle.ps1'
        def invoke(action,*args):
            result=subprocess.run(['pwsh','-NoProfile','-File',str(wrapper),'-Action',action,
                '-ProjectDirectory',str(self.root),'-RunDirectory',str(self.run),
                '-PythonPath',sys.executable,*args],capture_output=True,text=True,check=True)
            return json.loads(result.stdout)
        job=invoke('Prepare')
        self.assertEqual(job['status'],'READY_FOR_WORK')
        answer=self.answer(job,compact=True)
        self.assertEqual(invoke('Accept','-TaskId',job['task_id'],'-ResultPath',str(answer))['status'],'IMPORTED')
        self.assertEqual(invoke('Recover','-TaskId',job['task_id'])['status'],'ALREADY_IMPORTED')
        self.assertEqual(invoke('Status')['status'],'WORK_STATUS')

    def test_input_tamper_blocks_import(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        Path(job['input_path']).write_text('changed prompt',encoding='utf-8')
        result=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(result['status'],'STALE_OR_SUPERSEDED')
        self.assertFalse((self.run/'ledger.jsonl').exists())

    def test_raw_response_tamper_is_rejected(self):
        job=self.cycle('Prepare'); path=self.answer(job,bad=True)
        self.cycle('Accept',task_id=job['task_id'],response_path=path)
        folder=self.run/'jobs'/job['task_id']
        raw=work.raw_files(folder,self.root)[0]
        raw.write_bytes(b'{}')
        with self.assertRaisesRegex(core.K1LiteV2Error,'RESPONSE_TAMPERED'):
            self.cycle('Recover',task_id=job['task_id'])

    def test_partial_candidate_repair_preserves_coverage(self):
        job=self.cycle('Prepare'); path=self.answer(job,compact=True)
        value=json.loads(path.read_bytes())
        chunk=self.chunks[0]
        page=next(p for p in self.doc.pages if f'P{p.number:04d}' in chunk['pages'])
        good={'local_id':'A','page':f'P{page.number:04d}', 'quote':'The comet impact happened',
              'claim':'The source contains this statement.', 'category':'OPEN_DISCOVERY',
              'speaker_mode':'AUTHOR_CLAIM','film_value':1,'risk':1,'facts':[]}
        bad={**good,'quote':'This fabricated sentence is absent from the document.'}
        value.update(candidates=[bad],status='PARTIAL_OVERFLOW',more_strong_candidates=True)
        write_json(path,value)
        result=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(result['status'],'NEEDS_CORRECTION')
        detail=json.loads(Path(result['detail_path']).read_bytes())
        self.assertTrue(detail['candidate_errors'][0]['source_page'])
        fix=self.run/'incoming/fix.json'
        write_json(fix,{'schema':work.REPAIR,'task_id':job['task_id'],
            'base_response_sha256':detail['base_response_sha256'],'replacements':[good]})
        accepted=self.cycle('Accept',task_id=job['task_id'],response_path=fix)
        self.assertEqual(accepted['status'],'IMPORTED',accepted)
        pending=self.cycle('Prepare')
        _,request=work.read_request(self.run,self.root,pending['task_id'])
        self.assertEqual(request['continuation_no'],1)
        self.assertEqual(len(request['previous_candidates']),1)
        self.assertFalse(core.coverage_state(self.chunks,core.read_jsonl(self.run/'ledger.jsonl'))[0]['complete'])

    def test_wrong_task_compact_reply_is_preserved_but_rejected(self):
        job=self.cycle('Prepare'); path=self.answer(job,compact=True)
        value=json.loads(path.read_bytes()); value['task_id']='A'*64; write_json(path,value)
        result=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(result['status'],'NEEDS_CORRECTION')
        self.assertFalse((self.run/'ledger.jsonl').exists())

    def test_failure_after_ledger_replace_keeps_receipts(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        original=batch_import.append_ledger
        def committed_then_failed(*args,**kwargs):
            original(*args,**kwargs)
            raise OSError('lost confirmation')
        with patch('batch_import.append_ledger',side_effect=committed_then_failed):
            result=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(result['status'],'RETRY_LOCAL')
        self.assertTrue(list((self.run/'results').glob('*.json')))
        self.assertEqual(self.cycle('Recover',task_id=job['task_id'])['status'],'ALREADY_IMPORTED')
        core.validate_run(isolation_root=self.root,run_dir=self.run)

    def test_unrelated_ledger_change_does_not_require_new_answer(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        other=self.run/'incoming/other.json'
        write_json(other,make_result(self.info,self.chunks[-1],candidates=[]))
        core.import_worker_result(isolation_root=self.root,run_dir=self.run,result_path=other,expected_ledger_sha='CREATE_NEW')
        self.assertEqual(self.cycle('Prepare')['task_id'],job['task_id'])
        self.assertEqual(self.cycle('Accept',task_id=job['task_id'],response_path=path)['status'],'IMPORTED')

    def test_compact_output_reduces_metadata_without_cutting_evidence(self):
        job=self.cycle('Prepare'); canonical=self.answer(job).read_bytes()
        compact=self.answer(job,compact=True).read_bytes()
        self.assertLess(len(compact),len(canonical))
        self.assertEqual(json.loads(compact)['probe_answers'],json.loads(canonical)['probe_answers'])

    def test_continuation_prompt_matches_validator(self):
        snapshot=batch_import.Snapshot(self.root,self.run)
        req=work.identity(snapshot,{'chunk_id':self.chunks[0]['chunk_id'],'continuations':1},'UNSPECIFIED','medium')
        packet=(self.run/'worker-input'/f"{self.chunks[0]['chunk_id']}.md").read_text('utf-8')
        rendered=work.render_input(req,core.sha256_bytes(work.json_bytes(req)),packet)
        header,body=rendered.split('## Treść\n\n',1)
        self.assertIn('probe_answers: {}',header)
        self.assertNotIn('Dla każdego znacznika kontrolnego PROBE zwróć',header)
        self.assertIn('local_id',header)
        self.assertIn('speaker_mode',header)
        self.assertEqual(body,packet.split('## Treść\n\n',1)[1])

    def test_write_failure_before_validation_requests_local_recovery(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        real=work.atomic_new
        def fail_canonical(p,data):
            if p.name.endswith('.canonical.json'): raise OSError('disk full')
            return real(p,data)
        with patch.object(work,'atomic_new',side_effect=fail_canonical):
            result=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(result['status'],'RETRY_LOCAL')
        self.assertTrue(result['response_preserved'])
        self.assertEqual(self.cycle('Recover',task_id=job['task_id'])['status'],'IMPORTED')

    def test_malformed_request_is_controlled_error(self):
        job=self.cycle('Prepare')
        write_json(self.run/'jobs'/job['task_id']/'request.json',[])
        with self.assertRaisesRegex(core.K1LiteV2Error,'WORK_REQUEST_TAMPERED'):
            self.cycle('Recover',task_id=job['task_id'])

    def test_legacy_prepared_input_is_reused_unchanged(self):
        snapshot=batch_import.Snapshot(self.root,self.run)
        request=work.identity(snapshot,work.queue(snapshot),'UNSPECIFIED','medium')
        request.pop('input_revision',None)
        task_id=core.sha256_bytes(work.json_bytes(request))
        folder=work.task_path(self.run,self.root,task_id)
        packet=(self.run/'worker-input'/f"{request['chunk_id']}.md").read_text('utf-8')
        data=work.render_input(request,task_id,packet).encode('utf-8')
        work.atomic_new(folder/'input.md',data)
        work.atomic_new(folder/'request.json',work.json_bytes(request))
        job=self.cycle('Prepare')
        self.assertEqual(job['task_id'],task_id)
        self.assertEqual((folder/'input.md').read_bytes(),data)
        self.assertEqual(self.cycle('Accept',task_id=task_id,response_path=self.answer(job))['status'],'IMPORTED')

    def test_read_failure_during_staging_is_local_retry(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        original=batch_import.require_file
        def fail_read(p,root):
            if p.name.endswith('.canonical.json'): raise OSError('temporary read failure')
            return original(p,root)
        with patch.object(batch_import,'require_file',side_effect=fail_read):
            result=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(result['status'],'RETRY_LOCAL')
        self.assertEqual(self.cycle('Recover',task_id=job['task_id'])['status'],'IMPORTED')

    def test_diagnostic_write_failure_is_local_retry(self):
        job=self.cycle('Prepare'); path=self.answer(job,bad=True)
        original=work.atomic_new
        def fail_report(p,data):
            if '.error-' in p.name: raise OSError('report write failure')
            return original(p,data)
        with patch.object(work,'atomic_new',side_effect=fail_report):
            result=self.cycle('Accept',task_id=job['task_id'],response_path=path)
        self.assertEqual(result['status'],'RETRY_LOCAL')
        self.assertEqual(self.cycle('Recover',task_id=job['task_id'])['status'],'NEEDS_CORRECTION')

    def test_malformed_transaction_blocks_orphan_adoption_cleanly(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        with patch('batch_import.append_ledger',side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.cycle('Accept',task_id=job['task_id'],response_path=path)
        data=work.json_bytes([])
        work.atomic_new(self.run/'batch-transactions'/(core.sha256_bytes(data)+'.json'),data)
        result=self.cycle('Recover',task_id=job['task_id'])
        self.assertEqual(result['status'],'RETRY_LOCAL')
        self.assertEqual(result['error'],'BATCH_TRANSACTION_INVALID')
        self.assertFalse((self.run/'ledger.jsonl').exists())

    def test_normal_import_does_not_read_transaction_history(self):
        job=self.cycle('Prepare'); path=self.answer(job)
        self.cycle('Accept',task_id=job['task_id'],response_path=path)
        job=self.cycle('Prepare'); path=self.answer(job)
        original=batch_import.require_file
        def reject_history(p,root):
            if p.parent.name=='batch-transactions': raise AssertionError('unnecessary history read')
            return original(p,root)
        with patch.object(batch_import,'require_file',side_effect=reject_history):
            self.assertEqual(self.cycle('Accept',task_id=job['task_id'],response_path=path)['status'],'IMPORTED')

    @unittest.skipUnless(os.name=='nt','Windows junction check')
    def test_project_junction_is_rejected_before_wrapper_lock(self):
        (self.root/'.system-v7').mkdir()
        (self.root/'sources').mkdir(exist_ok=True)
        alias=self.root/'project-alias'
        command="New-Item -ItemType Junction -Path '"+str(alias).replace("'","''")+"' -Target '"+str(self.root).replace("'","''")+"' | Out-Null"
        subprocess.run(['pwsh','-NoProfile','-Command',command],capture_output=True,check=True)
        try:
            with self.assertRaisesRegex(core.K1LiteV2Error,'WORK_REPARSE_POINT_BLOCKED'):
                work.cycle('Status',alias,self.run)
            wrapper=Path(__file__).resolve().parents[1]/'Invoke-K1WorkCycle.ps1'
            result=subprocess.run(['pwsh','-NoProfile','-File',str(wrapper),'-Action','Prepare',
                '-ProjectDirectory',str(alias),'-RunDirectory',str(self.run),'-PythonPath',sys.executable],
                capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('WORK_REPARSE_POINT_BLOCKED',result.stderr)
            self.assertFalse((self.root/'.system-v7/meta-write.lock').exists())
        finally: os.rmdir(alias)


if __name__=='__main__': unittest.main()
