import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import panel as p
import panel_read as io
from panel_k1 import read_run
from panel_read import FileStore, ReadError

class PanelTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.store = FileStore(self.root, p.open_shared)

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, ensure_ascii=False) if not isinstance(data, str) else data, encoding="utf-8", newline="\n")
        return path

    def meta(self, extra=""):
        return self.write("meta.md", "WORKFLOW_REVISION: " + p.V2_REVISION + "\nCURRENT_STAGE: K3\nNARRATIVE_ACT_SEQUENCE: ACT-001\n" + extra)

    def watcher(self):
        return p.AgentWatcher(self.root), p.Session("CODEX", "memory", 100)

    def event(self, w, s, typ, **fields):
        w.codex_line(s, json.dumps({"type":"event_msg","timestamp":"2026-09-14T12:00:00Z","payload":{"type":typ,**fields}}).encode())

    def test_iso_offsets(self):
        self.assertEqual(p.parse_ts("2026-09-14T12:00:00+02:00"),p.parse_ts("2026-09-14T10:00:00Z"))
        self.assertIsNone(p.parse_ts("2026-99-01T00:00:00Z"))

    def test_duplicate_meta(self):
        with self.assertRaises(ReadError):p.parse_meta("CURRENT_STAGE: K3\nCURRENT_STAGE: COMPLETE")

    def test_revision_checked_every_read(self):
        self.meta()
        self.assertTrue(p.collect_project(self.root)["ok"])
        self.write("meta.md","WORKFLOW_REVISION: legacy\nCURRENT_STAGE: K3\n")
        self.assertFalse(p.collect_project(self.root)["ok"])

    def test_bad_origin_is_visible(self):
        self.meta();self.write(".system-v7/project-origin.json",[])
        data=p.collect_project(self.root)
        self.assertFalse(data["ok"])
        self.assertIn("JSON",data["error"])

    def test_bad_run_is_isolated(self):
        self.meta();self.write("_work/narrative-runs/BAD/input-manifest.json","{broken")
        data=p.collect_project(self.root)
        self.assertTrue(data["ok"]);self.assertTrue(data["partial"]);self.assertIn("BAD",data["read_errors"][0])
        self.assertEqual(len(data["stages"]),9)

    def test_bad_stage(self):
        self.write("meta.md","WORKFLOW_REVISION: "+p.V2_REVISION+"\nCURRENT_STAGE: WHAT\n")
        self.assertFalse(p.collect_project(self.root)["ok"])

    def test_cached_reads_and_replacement(self):
        path=self.write("x.json",{"v":1})
        self.assertEqual(self.store.read(path,"json"),{"v":1})
        count=self.store.reads
        self.store.read(path,"json");self.assertEqual(self.store.reads,count)
        new=self.write("new.json",{"v":2});os.replace(new,path)
        self.assertEqual(self.store.read(path,"json"),{"v":2})

    def test_duplicate_json_rejected(self):
        path=self.write("x.json",'{"a":1,"a":2}')
        with self.assertRaises(ReadError):self.store.read(path,"json")

    def test_partial_ledger_is_not_complete(self):
        path=self.write("ledger.jsonl",'{"a":1}')
        with self.assertRaises(ReadError):self.store.read(path,"jsonl")

    def test_ledger_appends_preserved(self):
        path=self.write("ledger.jsonl",'{"a":1}\n')
        self.assertEqual(len(self.store.read(path,"jsonl")),1)
        with path.open("a") as f:f.write('{"a":2}\n')
        self.assertEqual(len(self.store.read(path,"jsonl")),2)

    def test_digest_invalidates(self):
        path=self.write("x.txt","AAA");old=self.store.digest(path)
        stamp=path.stat().st_mtime_ns
        self.write("x.txt","BBB");os.utime(path,ns=(stamp,stamp))
        self.assertNotEqual(self.store.digest(path),old)

    def test_path_traversal(self):
        for relative in ("../file","C:/file", "..\\file"):
            with self.assertRaises(ReadError):io.safe_relative(self.root,relative)

    def test_tail_partial(self):
        path=self.write("log",'{"a":')
        t=p.Tail(path,100)
        self.assertEqual(t.read_new(),[])
        with path.open("a") as f:f.write("1}\n")
        self.assertEqual(t.read_new(),[b'{"a":1}'])
        self.assertEqual(t.read_new(),[])

    def test_tail_oversized(self):
        path=self.write("log",'{"a":1}\n'+"x"*25)
        t=p.Tail(path,100)
        with patch.object(p,"MAX_LINE_BYTES",20):
            self.assertEqual(t.read_new(),[b'{"a":1}'])
            with path.open("a") as f:f.write('xx\n{"b":2}\n')
            self.assertEqual(t.read_new(),[b'{"b":2}'])

    def test_tail_same_size_replacement(self):
        path=self.write("log","old\n");t=p.Tail(path,100)
        self.assertEqual(t.read_new(),[b"old"])
        newer=self.write("new","new\n");os.replace(newer,path)
        self.assertEqual(t.read_new(),[b"new"])
        self.assertEqual(t.generation,1)

    def test_tail_larger_replacement(self):
        path=self.write("log","old\n");t=p.Tail(path,100);t.read_new()
        newer=self.write("new","new longer\n");os.replace(newer,path)
        self.assertEqual(t.read_new(),[b"new longer"])

    def test_tail_boundary_keeps_complete_line(self):
        path=self.write("log","old\nnew\n")
        self.assertEqual(p.Tail(path,4).read_new(),[b"new"])

    def test_codex_legacy_messages_and_whitespace(self):
        w,s=self.watcher()
        self.event(w,s,"task_started")
        self.event(w,s,"user_message",message=str(self.root))
        self.event(w,s,"agent_message",message="Trwa praca")
        self.assertEqual(len(s.events),2);self.assertTrue(s.working)

    def test_escaped_windows_path(self):
        w,s=self.watcher()
        self.assertTrue(w.mentions(json.dumps({"path":str(self.root)})))

    def test_no_parent_name_alias(self):
        w,s=self.watcher()
        self.assertFalse(w.mentions("Z:/other/"+self.root.parent.name+"/"+self.root.name))

    def test_prior_unrelated_events_not_retroactive(self):
        w,s=self.watcher();w.sessions["s"]=s
        w.add(s,1,"say","inne")
        w.message(s,2,"prompt",str(self.root),"old")
        self.assertEqual([e["text"] for e in w.timeline()],[str(self.root)])

    def test_switch_project(self):
        w,s=self.watcher();w.sessions["s"]=s
        w.message(s,1,"prompt",str(self.root),"old")
        w.message(s,2,"prompt","Teraz C:/inny-projekt","old")
        w.add(s,3,"say","inna praca")
        self.assertEqual(len(w.timeline()),1)

    def test_multiple_sessions_working(self):
        w,s=self.watcher();s.linked=s.context=s.working=True;s.last_ts=95
        idle=p.Session("CODEX","idle",100);idle.linked=True;idle.last_ts=99
        w.sessions={"s":s,"idle":idle}
        self.assertEqual(w.summary(100)["CODEX"]["status"],"working")

    def test_message_variant_dedup(self):
        w,s=self.watcher()
        w.message(s,1,"prompt",str(self.root),"user_message")
        w.message(s,2,"prompt",str(self.root),"item_completed")
        self.assertEqual(len(s.events),1)

    def test_failed_run_not_green(self):
        run={"run_id":"X","receipt":True,"output":True,"verdict":"FAIL"}
        self.assertEqual(p.run_cell(run,"wait")["state"],"fail")

    def test_receipt_without_prose_not_done(self):
        run={"run_id":"X","receipt":True,"output":True,"verdict":None}
        self.assertNotEqual(p.run_cell(run,"wait")["state"],"done")

    def test_standalone_attest_not_valid(self):
        self.meta();self.write("_work/k3/continuity/ACT-001.attest.json",{"verdict":"PASS"})
        data=p.collect_project(self.root)
        row=next(s for s in data["stages"] if s["key"]=="K3")["extra"]["acts"][0]
        self.assertFalse(row["attested"])

    def test_complex_requires_beat(self):
        self.meta();self.write("_work/k3/packets/ACT-001.act-packet.json",{"complexity_flag":"COMPLEX"})
        data=p.collect_project(self.root)
        row=next(s for s in data["stages"] if s["key"]=="K3")["extra"]["acts"][0]
        self.assertNotEqual(row["cells"]["beat"]["state"],"na")

    def test_k5_old_approval_not_green(self):
        self.meta();self.write("_work/K5/v2-approval-OLD.json",{})
        data=p.collect_project(self.root)
        k5=next(s for s in data["stages"] if s["key"]=="K5")
        self.assertNotEqual(k5["steps"][1]["state"],"done")

    def test_complete_meta_not_enough(self):
        self.write("meta.md","WORKFLOW_REVISION: "+p.V2_REVISION+"\nCURRENT_STAGE: COMPLETE\nLAST_GATE: K5_PASS\n")
        data=p.collect_project(self.root)
        self.assertNotEqual(data["stages"][-1]["status"],"done")

    def test_source_mapping_duplicates(self):
        self.write("sources/A.txt","A");self.write("sources/B.txt","B")
        ctx=p.Context(self.root,{"CURRENT_STAGE":"K1"})
        run={"run":"R1","source_relative":"sources/A.txt","source_current":True}
        runs,complete,detail=p.current_source_runs(ctx,[run,{**run,"run":"R2"}])
        self.assertFalse(complete);self.assertEqual(runs,[]);self.assertIn("B.txt".lower(),detail)

    def test_recent_files_bounded(self):
        for i in range(45):self.write(f"files/{i}.txt",str(i))
        result=p.recent_files(self.root,10)
        self.assertEqual(len(result),10)
        self.assertTrue(all("nie potwierdza" in x["detail"] for x in result))

    def test_snapshot_detects_changes(self):
        path=self.write("x","old");self.store.begin();self.store.read(path)
        self.write("x","new")
        self.assertFalse(self.store.stable())

    def test_cache_payload_bound(self):
        self.store.max_cache_bytes=12
        for i in range(4): self.store.read(self.write(str(i),"12345678"))
        self.assertLessEqual(sum(x["size"] for x in self.store.cache.values()),12)

    def test_extended_windows_cwd(self):
        w=p.AgentWatcher(Path("E:/zażółć gęślą/projekt"))
        self.assertTrue(w.inside("//?/E:/zażółć gęślą/projekt/src"))
        self.assertTrue(w.inside("file:///E:/za%C5%BC%C3%B3%C5%82%C4%87%20g%C4%99%C5%9Bl%C4%85/projekt"))

    def test_verifier_retries_transient_error(self):
        v=io.Verifier(self.root);v.key=(1,);v.result={"error":"temporary"};v.checked_mono=time.monotonic()-16
        with patch.object(io.threading.Thread,"start") as start:
            self.assertTrue(v.get((1,))["pending"]);start.assert_called_once()

    def test_verifier_unchanged_result_cached(self):
        v=io.Verifier(self.root);v.key=(1,);v.result={"origin":{"valid":True}};v.checked_mono=time.monotonic()
        with patch.object(io.threading.Thread,"start") as start:
            self.assertEqual(v.get((1,)),v.result);start.assert_not_called()
            self.assertTrue(v.get((2,))["pending"])

    def test_browser_fallback(self):
        with patch.object(p,"EDGE",self.write("edge.exe","")), patch.object(p.subprocess,"Popen",side_effect=OSError), patch.object(p.webbrowser,"open",return_value=True) as fallback:
            p.open_browser("http://127.0.0.1:1234/");fallback.assert_called_once()
        with patch.object(p,"EDGE",self.root/"missing"), patch.object(p.webbrowser,"open",return_value=False):
            with self.assertRaisesRegex(RuntimeError,"przeglądarki"):p.open_browser("http://127.0.0.1:1234/")

    def test_http_errors_are_structured(self):
        import http.client, threading
        from types import SimpleNamespace
        server=p.ThreadingHTTPServer(("127.0.0.1",0),None)
        port=server.server_address[1]
        app=SimpleNamespace(state=lambda: (_ for _ in ()).throw(ValueError("broken")))
        server.RequestHandlerClass=p.make_handler(app,port)
        worker=threading.Thread(target=server.serve_forever,daemon=True);worker.start()
        try:
            conn=http.client.HTTPConnection("127.0.0.1",port,timeout=3)
            conn.request("GET","/api/state");r=conn.getresponse();self.assertEqual(r.status,500);self.assertFalse(json.loads(r.read())["ok"])
            conn.request("GET","/api/state",headers={"Host":"outside.example"});r=conn.getresponse();self.assertEqual(r.status,403);r.read()
            conn.request("GET","/../../meta.md");r=conn.getresponse();self.assertEqual(r.status,404);r.read();conn.close()
        finally:server.shutdown();server.server_close();worker.join(2)

    def test_occupied_port_raises(self):
        import socket
        self.meta()
        with socket.socket() as sock:
            sock.bind(("127.0.0.1",0));sock.listen()
            with patch.object(sys,"argv",["panel.py",str(self.root),"--no-browser","--port",str(sock.getsockname()[1])]):
                with self.assertRaises(OSError):p.main()

    def test_launcher_missing_interpreter(self):
        if os.name != "nt":self.skipTest("Windows launcher")
        import subprocess
        env=dict(os.environ);env["PATH"]=str(Path(os.environ["SystemRoot"])/"System32")
        result=subprocess.run([env["COMSPEC"],"/d","/c",str(p.HERE/"Panel.bat")],env=env,input="\n",capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,1);self.assertIn("Python 3.10",result.stdout)

class RealK1Tests(unittest.TestCase):
    def test_existing_cycle_and_panel_agree(self):
        tools=io.SYSTEM_ROOT/"tools/k1-lite-v2"
        sys.path[:0]=[str(tools),str(tools/"tests")]
        from test_work_cycle import WorkCycleTests
        case=WorkCycleTests()
        case.setUp()
        try:
            store=FileStore(case.root,p.open_shared)
            first=case.cycle("Prepare")
            self.assertEqual(read_run(case.run,case.root,store)["tasks"][0]["status"],"WAITING_FOR_RESPONSE")
            bad=case.answer(first,bad=True)
            result=case.cycle("Accept",task_id=first["task_id"],response_path=bad)
            self.assertEqual(result["status"],"NEEDS_CORRECTION")
            self.assertEqual(read_run(case.run,case.root,store)["tasks"][0]["status"],"NEEDS_CORRECTION")
            good=case.answer(first,compact=True)
            accepted=case.cycle("Accept",task_id=first["task_id"],response_path=good)
            self.assertEqual(accepted["status"],"IMPORTED")
            before={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in case.root.rglob("*") if f.is_file()}
            state=read_run(case.run,case.root,store)
            self.assertEqual(state["waiting"],[])
            self.assertGreater(state["chunks_done"],0)
            after={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in case.root.rglob("*") if f.is_file()}
            self.assertEqual(before,after)
            marker=case.run/"jobs"/first["task_id"]/"accepted.json"
            marker.unlink()
            self.assertEqual(read_run(case.run,case.root,store)["tasks"][0]["status"],"CONFIRMATION_PENDING")
        finally:case.doCleanups()

if __name__=="__main__":
    unittest.main(verbosity=2)
