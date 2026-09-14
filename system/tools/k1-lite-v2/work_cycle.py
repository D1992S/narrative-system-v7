"""File-based K1 work cycle. Never invokes an LLM or grants an evidence gate."""
import argparse
import json
import re
import sys
from pathlib import Path
import k1_lite_v2_core as core
from batch_import import Snapshot, stage, commit, preview_batch
from work_io import safe, atomic_new, json_bytes, run_lock

CONTRACT = 'K1_WORK_TASK_V1'
REPLY = 'K1_WORK_REPLY_V1'
REPAIR = 'K1_WORK_REPAIR_V1'
TASK_RE = re.compile(r'^[A-F0-9]{64}$')
RAW_RE = re.compile(r'^a(\d{6})-([A-F0-9]{64})\.json$')


def queue(snapshot):
    pending = [c for c in core.coverage_state(snapshot.chunks, snapshot.ledger) if not c['complete']]
    return pending[0] if pending else None


def identity(snapshot, item, model, effort, input_revision=2):
    chunk = snapshot.chunk_map[item['chunk_id']]
    previous = [{'candidate_id':e['candidate_id'], 'quote':e['quote'], 'page':e['page']}
                for e in snapshot.ledger if e.get('event_type')=='candidate'
                and e.get('chunk_id')==item['chunk_id'] and e['continuation_no'] < item['continuations']]
    request = {'schema':CONTRACT,'run_id':snapshot.run['run_id'],
            'analysis_key':snapshot.run['analysis_key'],'chunk_id':item['chunk_id'],
            'chunk_sha256':chunk['chunk_sha256'],'packet_sha256':chunk['packet_sha256'],
            'continuation_no':item['continuations'],'candidate_limit':snapshot.run.get('candidate_limit',2),
            'previous_candidates':previous,'model':model,'effort':effort}
    if input_revision != 1: request['input_revision']=input_revision
    return request


def task_path(run, root, task_id):
    if not TASK_RE.fullmatch(task_id or ''): raise core.K1LiteV2Error('WORK_TASK_ID_INVALID')
    return safe(run/'jobs'/task_id, root)


def read_request(run, root, task_id):
    folder=task_path(run,root,task_id)
    request=json.loads(safe(folder/'request.json',root).read_bytes())
    if not isinstance(request,dict) or request.get('schema')!=CONTRACT or core.sha256_bytes(json_bytes(request))!=task_id:
        raise core.K1LiteV2Error('WORK_REQUEST_TAMPERED')
    if type(request.get('input_revision',1)) is not int or request.get('input_revision',1) not in (1,2):
        raise core.K1LiteV2Error('WORK_INPUT_REVISION_UNSUPPORTED')
    return folder,request


def raw_files(folder, root):
    files=[]
    for path in safe(folder,root).glob('a*.json'):
        match=RAW_RE.fullmatch(path.name)
        if match:
            path=safe(path,root)
            if core.sha256_file(path)!=match[2]: raise core.K1LiteV2Error('WORK_RESPONSE_TAMPERED')
            files.append(path)
    return sorted(files)


def store_response(folder, root, response_path):
    data=safe(response_path,root).read_bytes()
    if len(data)>4_000_000: raise core.K1LiteV2Error('WORK_RESPONSE_TOO_LARGE')
    digest=core.sha256_bytes(data)
    previous=raw_files(folder,root)
    for path in previous:
        if RAW_RE.fullmatch(path.name)[2]==digest: return path
    number=1+max([int(RAW_RE.fullmatch(p.name)[1]) for p in previous],default=0)
    path=safe(folder/f'a{number:06d}-{digest}.json',root)
    atomic_new(path,data)
    return path


def canonical(request, task_id, payload):
    if not isinstance(payload,dict): raise core.K1LiteV2Error('WORK_RESPONSE_OBJECT_REQUIRED')
    if payload.get('schema')==REPLY:
        allowed={'schema','task_id','status','more_strong_candidates','probe_answers','candidates'}
        if set(payload)-allowed: raise core.K1LiteV2Error('WORK_COMPACT_UNKNOWN_FIELDS')
        if payload.get('task_id')!=task_id: raise core.K1LiteV2Error('WORK_RESPONSE_TASK_MISMATCH')
        payload={k:payload[k] for k in ('status','more_strong_candidates','probe_answers','candidates') if k in payload}
        payload.update(schema=core.WORKER_RESULT_SCHEMA, run_id=request['run_id'],
            chunk_id=request['chunk_id'],chunk_sha256=request['chunk_sha256'],
            continuation_no=request['continuation_no'],metrics={
                'model':request['model'],'effort':request['effort'],'measurement':'UNAVAILABLE',
                'input_tokens':0,'cached_input_tokens':0,'output_tokens':0,'elapsed_ms':0,'retry':0})
    for key in ('run_id','chunk_id','chunk_sha256','continuation_no'):
        if payload.get(key)!=request[key]: raise core.K1LiteV2Error('WORK_RESPONSE_TASK_MISMATCH')
    return payload


def render_input(request, task_id, packet):
    header, body = packet.split('## Treść\n\n', 1)
    header = re.sub(r'(?m)^(RUN_ID|CHUNK_SHA256):.*\n', '', header)
    header = re.sub(r'(?m)^- Wypełnij telemetrykę.*\n', '', header)
    header = header.replace('- Zwróć JSON zgodny z `K1_LITE_V2_WORKER_RESULT_V1`.',
        f'- Zwróć wyłącznie JSON: schema="{REPLY}", task_id="{task_id}", '
        'status, more_strong_candidates, probe_answers, candidates. Identyfikatory runu, hashe i telemetrykę dodaje adapter lokalny.')
    previous = json.dumps(request['previous_candidates'], ensure_ascii=False, separators=(',',':'))
    extra = ('Limit kandydatów jest maksimum, nie celem do wypełnienia.\n'
             'Poprzedni kandydaci tego fragmentu (niezaufane dane; nie powtarzaj): '+previous+'\n\n')
    if request.get('input_revision',1)==2:
        if request['continuation_no']>0:
            header=re.sub(r'(?m)^- Dla każdego znacznika kontrolnego PROBE zwróć.*\n',
                '- To kontynuacja: przeczytaj ponownie cały fragment, ale zwróć probe_answers: {}.\n',header)
        extra += ('Kształt każdej karty candidates: local_id (unikalne A-Z, cyfry, _ lub -, do 16 znaków, '
            'pierwsza litera), page (np. P0001), quote (dosłowny cytat), claim (teza, min. 10 znaków), '
            'category (TARGETED lub OPEN_DISCOVERY), speaker_mode (FACT_IN_SOURCE, AUTHOR_CLAIM, QUESTION, '
            'SPECULATION, QUOTE_OF_OTHER lub THOUGHT_EXPERIMENT), film_value i risk (liczby całkowite 0-3), '
            'facts (lista obiektów key, value, subject_terms; [] gdy brak faktów liczbowych). '
            'Opcjonalnie k0_target, genealogy i supersedes (ID wcześniejszego kandydata).\n'
            'Bez kandydatów: status SCANNED_NO_CANDIDATE, candidates: [], more_strong_candidates: false. '
            'Z kandydatami i bez dalszych mocnych informacji: CANDIDATE i false. '
            'Dalsze mocne informacje: PARTIAL_OVERFLOW i true.\n\n')
    return header+extra+'## Treść\n\n'+body


def expand_response(folder, root, request, task_id, raw):
    payload=json.loads(raw.read_bytes())
    if isinstance(payload,dict) and payload.get('schema')==REPAIR:
        if set(payload)!={'schema','task_id','base_response_sha256','replacements'} or payload['task_id']!=task_id:
            raise core.K1LiteV2Error('WORK_REPAIR_INVALID')
        base=next((p for p in raw_files(folder,root) if RAW_RE.fullmatch(p.name)[2]==payload['base_response_sha256'] and p.name<raw.name),None)
        if base is None: raise core.K1LiteV2Error('WORK_REPAIR_BASE_MISSING')
        base_payload=json.loads(base.read_bytes())
        if not isinstance(base_payload,dict): raise core.K1LiteV2Error('WORK_REPAIR_BASE_INVALID')
        if base_payload.get('schema')==REPAIR: raise core.K1LiteV2Error('WORK_REPAIR_CHAIN_NOT_ALLOWED')
        result=canonical(request,task_id,base_payload)
        replacements=payload['replacements']
        if not isinstance(replacements,list) or not replacements: raise core.K1LiteV2Error('WORK_REPAIR_EMPTY')
        candidates=result.get('candidates',[])
        if not isinstance(candidates,list) or any(not isinstance(c,dict) or not isinstance(c.get('local_id'),str) for c in candidates):
            raise core.K1LiteV2Error('WORK_REPAIR_BASE_INVALID')
        mapping={c['local_id']:i for i,c in enumerate(candidates)}
        seen=set()
        for candidate in replacements:
            if not isinstance(candidate,dict): raise core.K1LiteV2Error('WORK_REPAIR_CANDIDATE_INVALID')
            local_id=candidate.get('local_id')
            if local_id not in mapping or local_id in seen: raise core.K1LiteV2Error('WORK_REPAIR_CANDIDATE_INVALID')
            seen.add(local_id); candidates[mapping[local_id]]=candidate
        return result  # Coverage/probes/continuation are inherited, never granted by repair.
    return canonical(request,task_id,payload)


def assert_current(snapshot, request):
    chunk=snapshot.chunk_map.get(request['chunk_id'])
    if not chunk or request['analysis_key']!=snapshot.run['analysis_key'] or request['packet_sha256']!=chunk['packet_sha256']:
        raise core.K1LiteV2Error('WORK_TASK_STALE')
    prior=[e for e in snapshot.ledger if e.get('event_type')=='chunk_result' and e.get('chunk_id')==request['chunk_id']]
    if len(prior)!=request['continuation_no']: raise core.K1LiteV2Error('WORK_TASK_SUPERSEDED')
    current=identity(snapshot,{'chunk_id':request['chunk_id'],'continuations':len(prior)},request['model'],request['effort'],request.get('input_revision',1))
    if current!=request: raise core.K1LiteV2Error('WORK_TASK_STALE')
    task_id=core.sha256_bytes(json_bytes(request))
    packet=(snapshot.path/'worker-input'/(request['chunk_id']+'.md')).read_text(encoding='utf-8')
    expected=render_input(request,task_id,packet).encode('utf-8')
    path=safe(snapshot.path/'jobs'/task_id/'input.md',snapshot.root)
    if path.read_bytes()!=expected: raise core.K1LiteV2Error('WORK_INPUT_TAMPERED')


def correction_context(snapshot, folder, task_id, request, result, raw, error):
    problems=[]
    if isinstance(result,dict) and isinstance(result.get('candidates'),list):
        for candidate in result['candidates']:
            if not isinstance(candidate,dict): continue
            single={**result,'candidates':[candidate],'status':'CANDIDATE','more_strong_candidates':False}
            try:
                core.validate_worker_result(result=single,run=snapshot.run,
                    chunk=snapshot.chunk_map[request['chunk_id']],document=snapshot.document,
                    ledger=snapshot.ledger,isolation_root=snapshot.root)
            except (core.K1LiteV2Error,ValueError,KeyError,TypeError) as exc:
                page=candidate.get('page')
                allowed=snapshot.chunk_map[request['chunk_id']]['pages']
                context=next((p.body for p in snapshot.document.pages if f'P{p.number:04d}'==page and page in allowed),None)
                problems.append({'local_id':candidate.get('local_id'),'error':str(exc)[:300],
                    'page':page,'source_page':context})
    report={'schema':'K1_WORK_CORRECTION_V1','task_id':task_id,
        'base_response_sha256':core.sha256_file(raw),'error':str(error)[:400],
        'candidate_errors':problems,
        'instruction':'Repair only identified candidates using the source context. Do not change coverage, probes or continuation. If context is missing, use the unchanged full input.',
        'repair_schema':REPAIR}
    path=safe(folder/(raw.stem+'.error.json'),snapshot.root)
    # Diagnostics may differ after a changed ledger: immutable by content hash.
    path=path.with_name(raw.stem+'.error-'+core.sha256_bytes(json_bytes(report))[:12]+'.json')
    atomic_new(path,json_bytes(report))
    return path


def process(snapshot, folder, request, task_id, raw):
    result=None
    try:
        result=expand_response(folder,snapshot.root,request,task_id,raw)
        data=json_bytes(result)
        digest=core.sha256_bytes(data)
        receipt=next((e for e in snapshot.ledger if e.get('event_type')=='result_receipt'
            and e.get('chunk_id')==request['chunk_id'] and e.get('continuation_no')==request['continuation_no']),None)
        if receipt:
            if receipt['result_sha256']!=digest: raise core.K1LiteV2Error('WORK_ALREADY_COMPLETED_DIFFERENT_RESPONSE')
            stored=safe(snapshot.root/receipt['stored_relative'],snapshot.root)
            core.verify_file_sha(stored,digest,'WORK_IMPORTED_RECEIPT')
            return {'status':'ALREADY_IMPORTED','task_id':task_id,'new_model_call_required':False}
        assert_current(snapshot,request)
        path=safe(folder/(raw.stem+'.canonical.json'),snapshot.root)
        atomic_new(path,data)
        staged=stage(snapshot,[path])
    except (core.K1LiteV2Error,ValueError,UnicodeError,KeyError,TypeError) as exc:
        if str(exc).startswith(('WORK_TASK_STALE','WORK_TASK_SUPERSEDED','WORK_ALREADY_COMPLETED','WORK_INPUT_TAMPERED')):
            return {'status':'STALE_OR_SUPERSEDED','task_id':task_id,'error':str(exc),
                    'response_preserved':True,'automatic_model_retry':False}
        try: detail=correction_context(snapshot,folder,task_id,request,result,raw,exc)
        except OSError as local_error:
            return {'status':'RETRY_LOCAL','task_id':task_id,'error':str(local_error)[:300],
                    'response_preserved':True,'new_model_call_required':False}
        return {'status':'NEEDS_CORRECTION','task_id':task_id,'error':str(exc)[:300],
            'detail_path':str(detail),'response_preserved':True,'automatic_model_retry':False}
    except OSError as exc:
        return {'status':'RETRY_LOCAL','task_id':task_id,'error':str(exc)[:300],
                'response_preserved':True,'new_model_call_required':False}
    try:
        imported=commit(snapshot,staged,snapshot.ledger_sha)
    except (core.K1LiteV2Error,OSError) as exc:
        return {'status':'RETRY_LOCAL','task_id':task_id,'error':str(exc)[:300],
                'response_preserved':True,'new_model_call_required':False}
    marker={'task_id':task_id,'result_sha256':digest}
    try:
        atomic_new(safe(folder/'accepted.json',snapshot.root),json_bytes(marker))
    except OSError as exc:
        return {'status':'CONFIRMATION_PENDING','task_id':task_id,'error':str(exc)[:200],
                'response_preserved':True,'new_model_call_required':False}
    pending=queue(snapshot)
    return {'status':'IMPORTED','task_id':task_id,'candidates':len(result['candidates']),
        'next_chunk':pending['chunk_id'] if pending else None,
        'analysis_complete':pending is None,'review_required':True,'ledger_sha256':imported['ledger_sha256']}


def prepare(snapshot, model='UNSPECIFIED', effort='medium'):
    if not isinstance(model,str) or not model.strip() or effort not in core.ALLOWED_EFFORTS:
        raise core.K1LiteV2Error('WORK_EXECUTION_POLICY_INVALID')
    pending=queue(snapshot)
    if pending is None: return {'status':'ANALYSIS_COMPLETE_REVIEW_REQUIRED','new_model_call_required':False}
    request=identity(snapshot,pending,model,effort)
    # A different execution setting must not create a concurrent task for the same unit.
    jobs=safe(snapshot.path/'jobs',snapshot.root)
    for existing in jobs.glob('*/request.json'):
        _, prior=read_request(snapshot.path,snapshot.root,existing.parent.name)
        if prior['chunk_id']==request['chunk_id'] and prior['continuation_no']==request['continuation_no']:
            expected=identity(snapshot,pending,model,effort,prior.get('input_revision',1))
            if prior!=expected: raise core.K1LiteV2Error('WORK_EXISTING_TASK_POLICY_DIFFERS')
            request=prior  # Keep the input contract of an already prepared task.
    task_id=core.sha256_bytes(json_bytes(request))
    folder=task_path(snapshot.path,snapshot.root,task_id)
    existed=(folder/'request.json').exists()
    if existed:
        _,stored=read_request(snapshot.path,snapshot.root,task_id)
        if stored!=request: raise core.K1LiteV2Error('WORK_REQUEST_TAMPERED')
        responses=raw_files(folder,snapshot.root)
        if responses: return process(snapshot,folder,request,task_id,responses[-1])
    packet=snapshot.path/'worker-input'/(request['chunk_id']+'.md')
    text=render_input(request,task_id,packet.read_text(encoding='utf-8'))
    snapshot.check()
    # input first, request last: request is the publication marker for a prepared task.
    atomic_new(safe(folder/'input.md',snapshot.root),text.encode('utf-8'))
    atomic_new(safe(folder/'request.json',snapshot.root),json_bytes(request))
    return {'status':'WAITING_FOR_RESPONSE' if existed else 'READY_FOR_WORK','task_id':task_id,
        'input_path':str(folder/'input.md'),'response_path':str(folder/'reply.json'),
        'planned_input_characters':len(text),'new_model_call_required':not existed,
        'instruction':'Use this task once. Repeated Prepare is not authorization to dispatch again.'}


def cycle(action,root,run,*,task_id=None,response_path=None,model='UNSPECIFIED',effort='medium',result_paths=None):
    root=safe(root,root)
    run=core.ensure_run_location(safe(run,root),root)
    if action=='Status':
        snapshot=Snapshot(root,run)
        jobs=safe(run/'jobs',root)
        prepared=list(jobs.glob('*/request.json'))
        requests=[read_request(run,root,p.parent.name)[1] for p in prepared]
        responses=[raw for p in prepared for raw in raw_files(p.parent,root)]
        repairs=0
        for raw in responses:
            try: payload=json.loads(raw.read_bytes())
            except (ValueError,UnicodeError): continue
            repairs+=int(isinstance(payload,dict) and payload.get('schema')==REPAIR)
        snapshot.check()
        return {'status':'WORK_STATUS','pending_chunks':sum(not c['complete'] for c in core.coverage_state(snapshot.chunks,snapshot.ledger)),
            'prepared_tasks':len(prepared),'saved_responses':len(responses),
            'prepared_continuations':sum(r['continuation_no']>0 for r in requests),
            'saved_repair_responses':repairs,
            'published_results':sum(e.get('event_type')=='result_receipt' for e in snapshot.ledger),
            'planned_input_characters':sum(len(safe(p.parent/'input.md',root).read_text('utf-8')) for p in prepared),
            'actual_llm_calls':'UNAVAILABLE','tokens':'UNAVAILABLE',
            'actual_resent_characters':'UNAVAILABLE','local_retry_attempts':'UNAVAILABLE',
            'ledger_sha256':snapshot.ledger_sha}
    with run_lock(run,root):
        if action=='PreviewBatch':
            return preview_batch(isolation_root=root,run_dir=run,result_paths=result_paths or [])
        if action in ('Accept','Recover'):
            folder,request=read_request(run,root,task_id)
            if action=='Accept':
                if response_path is None: raise core.K1LiteV2Error('WORK_RESPONSE_PATH_REQUIRED')
                raw=store_response(folder,root,response_path)
            else:
                files=raw_files(folder,root)
                if not files: return {'status':'WAITING_FOR_RESPONSE','task_id':task_id,'automatic_model_retry':False}
                raw=files[-1]
            # Raw answer is already safe even if inputs have become stale.
            try: snapshot=Snapshot(root,run)
            except (core.K1LiteV2Error,OSError) as exc:
                return {'status':'STALE_OR_BLOCKED','task_id':task_id,'error':str(exc)[:300],'response_preserved':True}
            return process(snapshot,folder,request,task_id,raw)
        if action=='Prepare':
            return prepare(Snapshot(root,run),model,effort)
        raise core.K1LiteV2Error('WORK_ACTION_INVALID')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--action',required=True,choices=['Prepare','Accept','Recover','Status','PreviewBatch'])
    parser.add_argument('--root',required=True,type=Path)
    parser.add_argument('--run',required=True,type=Path)
    parser.add_argument('--task-id')
    parser.add_argument('--response',type=Path)
    parser.add_argument('--result',type=Path,action='append',default=[])
    parser.add_argument('--model',default='UNSPECIFIED')
    parser.add_argument('--effort',default='medium',choices=sorted(core.ALLOWED_EFFORTS))
    args=parser.parse_args()
    try:
        result=cycle(args.action,args.root,args.run,task_id=args.task_id,response_path=args.response,
                     model=args.model,effort=args.effort,result_paths=args.result)
        print(json.dumps(result,ensure_ascii=True))
        return 0
    except (core.K1LiteV2Error,OSError,ValueError,KeyError,TypeError) as exc:
        print(json.dumps({'status':'ERROR','error':str(exc)[:400]}))
        return 2


if __name__=='__main__':
    sys.exit(main())
