const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const code = fs.readFileSync(require("node:path").join(__dirname,"../panel.html"),"utf8").match(/<script>([\s\S]*?)<\/script>/)[1];
const data = () => ({ok:true, project:{name:"Zażółć",path:"C:/test",revision:"V2"},stage:{effective:"W0"},
 stages:[{key:"W0",title:"Start",status:"current",steps:[]}],agents:{},pending_runs:[],waiting_for_dawid:[],timeline:[],errors:[]});
function setup(fetch) {
 const nodes=new Map(), timers=new Map();let id=0;
 const document={hidden:false,title:"",addEventListener(){},getElementById(key){if(!nodes.has(key))nodes.set(key,{innerHTML:"",textContent:"",className:"",hidden:false,addEventListener(){}});return nodes.get(key)}};
 const context={document,window:{addEventListener(){}},HTMLDetailsElement:class{},Date,AbortController,fetch,
  setTimeout(fn,ms){timers.set(++id,{fn,ms});return id},clearTimeout(i){timers.delete(i)}};
 vm.createContext(context);vm.runInContext(code,context);
 return {nodes,timers,context};
}
const settle=()=>new Promise(r=>setImmediate(r));
(async()=>{
 let count=0;
 let e=setup(async()=>({ok:true,json:async()=>data()}));await settle();
 assert.equal(e.nodes.get("live").className,"live");count++;
 e=setup(async()=>({ok:true,json:async()=>({ok:false,error:"brak meta"})}));await settle();
 assert.equal(e.nodes.get("live").className,"live off");count++;
 e=setup(async()=>({ok:false,status:500}));await settle();
 assert.equal(e.nodes.get("live").className,"live off");assert.ok(e.nodes.get("errors").innerHTML.includes("nieaktualne"));count++;
 e=setup(async()=>({ok:true,json:async()=>{throw Error("bad JSON")}}));await settle();
 assert.equal(e.nodes.get("live").className,"live off");count++;
 e=setup(async()=>({ok:true,json:async()=>({...data(),stale:true})}));await settle();
 assert.equal(e.nodes.get("live").className,"live off");count++;
 e=setup(async()=>({ok:true,json:async()=>({...data(),checking:true})}));await settle();
 assert.equal(e.nodes.get("live").className,"live off");count++;
 let calls=0;
 e=setup((url,options)=>{calls++;return new Promise((resolve,reject)=>options.signal.addEventListener("abort",()=>reject(Error("timeout"))))});
 await settle();vm.runInContext("tick()",e.context);assert.equal(calls,1);
 [...e.timers.values()].find(t=>t.ms===12000).fn();await settle();
 assert.ok([...e.timers.values()].some(t=>t.ms===2000));assert.equal(e.nodes.get("live").className,"live off");count++;
 e.context.fetch=async()=>({ok:true,json:async()=>data()});vm.runInContext("tick()",e.context);await settle();
 assert.equal(e.nodes.get("live").className,"live");count++;
 assert.equal(vm.runInContext('esc("<script>")',e.context),"&lt;script&gt;");count++;
 console.log("FRONTEND_PASS",count);
})().catch(e=>{console.error(e);process.exitCode=1});
