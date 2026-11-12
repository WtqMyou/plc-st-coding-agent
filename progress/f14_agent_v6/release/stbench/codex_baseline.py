"""Real Codex CLI transport with a local mock/controlled Responses gateway.

Shell and web tools are disabled for code-only candidate comparison. The common
outer judge supplies repair feedback to both frameworks. This is a documented
controlled baseline, not a benchmark of unrestricted Codex repository autonomy.
"""
from __future__ import annotations
import json
import os
import shutil
import subprocess
import threading
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from .providers.base import ProviderError, ProviderResponse
from .evaluation import atomic_json
from .process_control import run_logged


def response_events(text,model,usage=None):
    msg={"id":"msg_"+uuid.uuid4().hex,"type":"message","role":"assistant","status":"completed",
         "content":[{"type":"output_text","text":text,"annotations":[]}]}
    response={"id":"resp_"+uuid.uuid4().hex,"object":"response","created_at":int(time.time()),
              "status":"completed","model":model,"output":[msg],
              "usage":usage or {"input_tokens":0,"output_tokens":0,"total_tokens":0}}
    events=[{"type":"response.created","response":dict(response,status="in_progress",output=[])},
            {"type":"response.output_item.added","output_index":0,"item":dict(msg,status="in_progress",content=[])},
            {"type":"response.content_part.added","item_id":msg["id"],"output_index":0,"content_index":0,
             "part":{"type":"output_text","text":"","annotations":[]}},
            {"type":"response.output_text.delta","item_id":msg["id"],"output_index":0,"content_index":0,"delta":text},
            {"type":"response.output_text.done","item_id":msg["id"],"output_index":0,"content_index":0,"text":text},
            {"type":"response.content_part.done","item_id":msg["id"],"output_index":0,"content_index":0,"part":msg["content"][0]},
            {"type":"response.output_item.done","output_index":0,"item":msg},
            {"type":"response.completed","response":response}]
    return "".join("event: "+e["type"]+"\ndata: "+json.dumps(dict(e,sequence_number=i))+"\n\n"
                   for i,e in enumerate(events)).encode()


class ResponsesGateway:
    def __init__(self, *, mock_text=None, model="offline-fixture", spec=None, budget=None,max_tokens=16384,provider=None):
        self.mock_text,self.model,self.spec,self.budget,self.max_tokens=mock_text,model,spec,budget,max_tokens
        self.requests=[]
        self.cost_cny=0.
        self.actual_model=""
        self.usage={"prompt_tokens":0,"completion_tokens":0}
        self.token=uuid.uuid4().hex
        self.provider=provider
        self.request_allowance=1
        self.failure=None
    def __enter__(self):
        owner=self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args):
                pass
            def do_GET(self):
                self.send_error(404)
            def do_POST(self):
                if self.path not in ("/v1/responses","/responses") or self.headers.get("Authorization")!="Bearer "+owner.token:
                    self.send_error(403)
                    return
                body=self.rfile.read(int(self.headers.get("Content-Length","0")))
                job=json.loads(body)
                original_count=len(job.get("tools",[]))
                job["tools"]=[]
                job["tool_choice"]="none"
                owner.requests.append({"model":job.get("model"),"tools":[],"removed_tools_count":original_count,
                    "request_bytes":len(body)})
                try:
                    if job.get("model")!=owner.model:
                        raise ProviderError("Requested model identity mismatch")
                    if owner.provider is not None:
                        from .transport import responses_messages
                        if owner.request_allowance<=0:raise ProviderError("One upstream request per candidate; no implicit retries")
                        owner.request_allowance-=1
                        result=owner.provider.generate(responses_messages(job))
                        owner.actual_model=result.model
                        owner.usage={k:owner.usage[k]+result.usage[k] for k in owner.usage}
                        owner.cost_cny+=result.cost_cny
                        data=response_events(result.text,result.model,dict(input_tokens=result.usage['prompt_tokens'],
                            output_tokens=result.usage['completion_tokens'],total_tokens=sum(result.usage.values())))
                        content_type="text/event-stream"
                    elif owner.mock_text is not None:
                        data=response_events(owner.mock_text,owner.model)
                        content_type="text/event-stream"
                        owner.actual_model=owner.model
                    else:
                        if owner.spec is None or owner.budget is None:
                            raise ProviderError("Live gateway is not authorized")
                        job["max_output_tokens"]=owner.max_tokens
                        body=json.dumps(job).encode()
                        spec=owner.spec
                        upper=((len(body)+4096)*spec["input_cny_per_million"]+
                               owner.max_tokens*spec["output_cny_per_million"])/1e6
                        reservation=owner.budget.reserve(upper)
                        key=os.environ.get(spec["api_key_env"],"")
                        if not key:
                            raise ProviderError("Missing configured credential")
                        req=urllib.request.Request(spec["responses_base_url"].rstrip("/")+"/responses",data=body,
                            headers={"Content-Type":"application/json","Authorization":"Bearer "+key},method="POST")
                        with urllib.request.urlopen(req,timeout=180) as upstream:
                            data=upstream.read()
                            content_type=upstream.headers.get("Content-Type","text/event-stream")
                        usage=None
                        for line in data.decode("utf-8").splitlines():
                            if line.startswith("data: "):
                                event=json.loads(line[6:])
                                if event.get("type")=="response.completed":
                                    usage=event["response"].get("usage")
                                    owner.actual_model=event["response"].get("model","")
                        if not owner.actual_model or usage is None:
                            raise ProviderError("Missing upstream identity or usage; reservation retained")
                        if usage is not None:
                            cost=(usage["input_tokens"]*spec["input_cny_per_million"]+
                                  usage["output_tokens"]*spec["output_cny_per_million"])/1e6
                            owner.budget.settle(reservation,cost)
                            owner.cost_cny+=cost
                            owner.usage["prompt_tokens"]+=usage["input_tokens"]
                            owner.usage["completion_tokens"]+=usage["output_tokens"]
                    self.send_response(200)
                    self.send_header("Content-Type",content_type)
                    self.send_header("Content-Length",str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                except Exception as exc:
                    if owner.failure is None:
                        owner.failure=exc if isinstance(exc,ProviderError) else ProviderError('Gateway '+type(exc).__name__)
                    self.send_error(502,type(exc).__name__)
        self.server=ThreadingHTTPServer(("127.0.0.1",0),Handler)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True)
        self.thread.start()
        self.url="http://127.0.0.1:"+str(self.server.server_port)+"/v1"
        return self
    def __exit__(self,*args):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)


class CodexProvider:
    def __init__(self,gateway,*,model,work_root,executable=None,mock=False,timeout=180):
        self.gateway,self.model,self.timeout=gateway,model,timeout
        self.name="codex-mock" if mock else "codex-cli"
        self.executable=executable or shutil.which("codex")
        if not self.executable:
            raise ProviderError("Codex CLI unavailable")
        self.work_root=Path(work_root)
        self.work_root.mkdir(parents=True,exist_ok=True)
    def generate(self,messages):
        self.gateway.request_allowance=1
        self.gateway.failure=None
        if self.gateway.provider:
            self.gateway.provider.last_charge=0.
            self.gateway.provider.last_receipt={}
            self.gateway.provider.timeout=min(self.gateway.provider.timeout,max(.01,self.timeout-2))
        work=self.work_root/uuid.uuid4().hex
        work.mkdir()
        # No dataset, reference files or test expected values are copied here.
        prompt="\n\n".join(m["role"]+":\n"+m["content"] for m in messages)
        provider='model_providers.stbench={name="STBench",base_url='+json.dumps(self.gateway.url)+',wire_api="responses",env_key="STBENCH_ISOLATED_KEY"}'
        args=[self.executable,"exec","--ignore-user-config","--skip-git-repo-check","--ephemeral",
              "--json","--sandbox","read-only","--cd",str(work),"-m",self.model,
              "-c",'model_provider="stbench"',"-c",provider,
              "-c","features.shell_tool=false","-c",'web_search="disabled"',
              "-c","features.remote_plugin=false","-c","features.plugins=false",
              "-c","apps._default.enabled=false","-c","features.multi_agent=false",
              "-c","features.hooks=false","-c","features.enable_request_compression=false","-"]
        allowed={"PATH","SYSTEMROOT","WINDIR","COMSPEC","PATHEXT","USERPROFILE","APPDATA",
                 "LOCALAPPDATA","PROGRAMDATA","TEMP","TMP","PROCESSOR_ARCHITECTURE","HOMEDRIVE","HOMEPATH"}
        env={k:v for k,v in os.environ.items() if k.upper() in allowed}
        env.update(STBENCH_ISOLATED_KEY=self.gateway.token,TEMP=str(self.work_root),TMP=str(self.work_root))
        returncode,timed_out,failure=run_logged(args,work=work,input_text=prompt,env=env,
            timeout=self.timeout,failure=lambda:self.gateway.failure)
        if failure is not None:
            raise failure
        if timed_out:
            raise ProviderError("Codex CLI timeout")
        stdout=(work/'events.jsonl').read_text(encoding='utf-8',errors='replace')
        text=""
        usage={}
        for line in stdout.splitlines():
            try:
                event=json.loads(line)
            except ValueError:
                continue
            if event.get("type")=="item.completed" and event.get("item",{}).get("type")=="agent_message":
                text=event["item"]["text"]
            if event.get("type")=="turn.completed":
                u=event.get("usage",{})
                usage={"prompt_tokens":u.get("input_tokens",0),"completion_tokens":u.get("output_tokens",0)}
        if returncode or not text:
            raise ProviderError("Codex CLI failed; isolated logs: "+str(work))
        if not self.gateway.actual_model:
            raise ProviderError("Codex upstream did not report its actual model")
        r=ProviderResponse(text=text,model=self.gateway.actual_model,
            usage=usage if self.gateway.mock_text is not None else dict(self.gateway.usage))
        r.cost_cny=self.gateway.cost_cny
        self.gateway.cost_cny=0.
        self.gateway.usage={"prompt_tokens":0,"completion_tokens":0}
        return r
    @property
    def last_charge(self):
        return self.gateway.provider.last_charge if self.gateway.provider else 0.
    @property
    def last_receipt(self):
        return self.gateway.provider.last_receipt if self.gateway.provider else {}
