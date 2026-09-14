"""Integration checks on the disposable fixture retained by Test-NarrativeV2.
Usage: python -B tests/check_fixture.py TEMP_REGRESSION_ROOT
Temporarily changes ONLY that explicitly named generated test fixture and restores bytes.
"""
import hashlib,json,subprocess,sys,time,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import panel as p
import panel_read as io
from panel_k1 import read_run
base=Path(sys.argv[1]).resolve()
assert base.parent==Path(tempfile.gettempdir()).resolve() and base.name.startswith('system-v7-narrative-v2-regression-')
root=base/'k3/PROJECT-COMPLEX'
def hashes():return {str(x.relative_to(root)):hashlib.sha256(x.read_bytes()).hexdigest() for x in root.rglob('*') if x.is_file()}
def proofs(project=root):
    r=subprocess.run(['pwsh','-NoProfile','-NonInteractive','-File',str(p.HERE/'Read-PanelProofs.ps1'),'-ProjectPath',str(project),'-SystemRoot',str(io.SYSTEM_ROOT)],capture_output=True,encoding='utf-8',timeout=90)
    assert r.returncode==0,r.stderr
    return json.loads(r.stdout.lstrip('\ufeff'))
results=[]
def check(name,condition):
    assert condition,name
    results.append(name)
def alter(path,fn):
    before=path.read_bytes()
    try:return fn(before)
    finally:path.write_bytes(before)
before=hashes();good=proofs()
check('native COMPLETE valid',all(good[x]['valid'] for x in ['origin','publication','assembly','k4','k5']))
data=p.collect_project(root,proofs=good)
check('panel COMPLETE valid',data['ok'] and not data['partial'] and data['stages'][-1]['status']=='done')
check('K3 all bindings valid',all(c['state']=='done' for c in next(s for s in data['stages'] if s['key']=='K3')['extra']['acts'][0]['cells'].values()))
final=root/'05-FINAL-SCRIPT.md'
def bad_final(b):
    final.write_bytes(b+b'!');bad=proofs();check('one byte final invalidates K5',not bad['k5']['valid'])
    check('modified final not COMPLETE',p.collect_project(root,proofs=bad)['stages'][-1]['status']!='done')
alter(final,bad_final)
draft=root/'03-draft.md'
def bad_draft(b):
    draft.write_bytes(b+b'!');bad=proofs();check('draft invalidates proof set',not bad['k4']['valid']);check('draft invalidates assembly',not bad['assembly']['valid'])
alter(draft,bad_draft)
run=root/'_work/K1/k1-lite-v2/full-chain-source-1';ledger=run/'ledger.jsonl'
original=json.loads((run/'run.json').read_text(encoding='utf-8-sig'))
def state():return read_run(run,root,io.FileStore(root,p.open_shared))
check('K1 initial review valid',state()['review'])
def variants(b):
    rows=[json.loads(x) for x in b.decode().splitlines()]
    def write(rs):ledger.write_text(''.join(json.dumps(x,ensure_ascii=False)+'\n' for x in rs),encoding='utf-8')
    selected=[x for x in rows if not(x.get('event_type')=='decision' and x.get('actor')=='DAWID')]
    write(selected);check('KEY_CHATGPT selects without Dawid decision',state()['selected']==1)
    decision=next(x for x in rows if x.get('event_type')=='decision' and x.get('actor')=='DAWID').copy();decision['decision']='REJECTED'
    write(selected+[decision]);check('Dawid rejection overrides recommendation',state()['selected']==0)
    decision['candidate_quote_sha256']='0'*64
    write(rows+[decision]);st=state();check('stale decision invalidates review',not st['review']);check('changed ledger invalidates report',st['gates_total']==0)
alter(ledger,variants)
source=root/original['source_relative']
def bad_source(b):
    source.write_bytes(b+b'changed');st=state();check('source modification invalidates source and review',not st['source_current'] and not st['review'])
alter(source,bad_source)
# A malformed one-gate report with a fresh timestamp must not win over integrity checks.
view=next((run/'views').glob('*/compile-report.json'))
def bad_report(b):
    r=json.loads(b);r['gates']={'coverage_ready':True};r['ledger_sha256']=hashlib.sha256(ledger.read_bytes()).hexdigest().upper()
    view.write_text(json.dumps(r),encoding='utf-8');check('one gate not six',state()['gates_total']==0)
alter(view,bad_report)
runfile=run/'run.json'
def visual_failure(b):
    r=json.loads(b);r['visual_policy']='REQUIRED';runfile.write_text(json.dumps(r),encoding='utf-8')
    def ledger_failure(lb):
        rows=[json.loads(x) for x in lb.decode().splitlines()];candidate=next(x for x in rows if x.get('event_type')=='candidate')
        rows.append({'event_type':'visual_receipt','candidate_id':candidate['candidate_id'],'verdict':'FAIL','quote_sha256':candidate['quote_sha256'],'source_sha256':r['source_sha256']})
        ledger.write_text(''.join(json.dumps(x)+'\n' for x in rows),encoding='utf-8')
        check('visual FAIL cannot count as confirmed quote',state()['visual']==0)
    alter(ledger,ledger_failure)
alter(runfile,visual_failure)
attest=root/'_work/k3/continuity/ACT-001.attest.json'
def bad_attest(b):
    attest.write_bytes(b+b'!');bad=proofs();check('broken attest invalidates continuity',not bad['acts']['ACT-001']['attest']['valid'])
alter(attest,bad_attest)
check('all project contents unchanged after checks',before==hashes())
# No API/OCR: synthetic ledger exercises parsing cache and one append.
with tempfile.TemporaryDirectory() as tmp:
    d=Path(tmp);f=d/'ledger.jsonl';f.write_text(''.join(json.dumps({'i':i})+'\n' for i in range(15000)),encoding='utf-8')
    store=io.FileStore(d,p.open_shared);t=time.perf_counter();store.read(f,'jsonl');first=time.perf_counter()-t;reads=store.reads
    t=time.perf_counter();store.read(f,'jsonl');second=time.perf_counter()-t;check('unchanged ledger no full reread',store.reads==reads)
    with f.open('a') as out:out.write('{"i":15000}\n')
    check('ledger append preserved',len(store.read(f,'jsonl'))==15001)
    perf={'records':15000,'first_seconds':first,'unchanged_seconds':second,'first_reads':reads,'unchanged_additional_reads':0,'append_additional_reads':store.reads-reads,'note':'Append parsing is incremental; changed prefix bytes are read for integrity.'}
print(json.dumps({'status':'PASS','checks':results,'performance':perf,'fixture':str(root)},ensure_ascii=False,indent=2))
