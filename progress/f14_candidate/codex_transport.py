"""Controlled CLI adapter preserving the F1.4 first user message.
Shared system guidance uses the documented developer_instructions setting.
The frozen historical transport is retained without modification.
"""
import json
import os
import uuid
from stbench.codex_baseline import CodexProvider
from stbench.process_control import stop_tree
from pathlib import Path
import subprocess
import time
from stbench.providers.base import ProviderError,ProviderResponse

def run_logged(args, *, work, input_text, env, timeout, failure=None):
    """Keep stdout/stderr on disk even on failure; stdin contains only the task prompt."""
    work = Path(work)
    prompt = work / 'prompt.txt'
    prompt.write_bytes(input_text.encode('utf-8'))
    options = dict(creationflags=subprocess.CREATE_NO_WINDOW) if os.name == 'nt' else dict(start_new_session=True)
    deadline = time.monotonic() + max(.01, timeout)
    with prompt.open('rb') as stdin, (work/'events.jsonl').open('xb') as stdout, (work/'stderr.log').open('xb') as stderr:
        process = subprocess.Popen(args, stdin=stdin, stdout=stdout, stderr=stderr, env=env, **options)
        try:
            while True:
                error = failure() if failure else None
                if error is not None:
                    stop_tree(process)
                    return process.returncode, False, error
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    stop_tree(process)
                    return process.returncode, True, None
                try:
                    return process.wait(timeout=min(.05, remaining)), False, None
                except subprocess.TimeoutExpired:
                    pass
        finally:
            if process.poll() is None:
                stop_tree(process)


class InitialTextCodexProvider(CodexProvider):
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
        conversation=[m for m in messages if m["role"]!="system"]
        developer="\n\n".join(m["content"] for m in messages if m["role"]=="system")
        if len(conversation)==1 and conversation[0]["role"]=="user":
            prompt=conversation[0]["content"]
        else:
            prompt="\n\n".join(m["role"]+":\n"+m["content"] for m in conversation)
        provider='model_providers.stbench={name="STBench",base_url='+json.dumps(self.gateway.url)+',wire_api="responses",env_key="STBENCH_ISOLATED_KEY"}'
        args=[self.executable,"exec","--ignore-user-config","--skip-git-repo-check","--ephemeral",
              "--json","--sandbox","read-only","--cd",str(work),"-m",self.model,
              "-c",'model_provider="stbench"',"-c",provider,
              "-c","features.shell_tool=false","-c",'web_search="disabled"',
              "-c","features.remote_plugin=false","-c","features.plugins=false",
              "-c","apps._default.enabled=false","-c","features.multi_agent=false",
              "-c","features.hooks=false","-c","features.enable_request_compression=false","-"]
        if developer:args[-1:-1]=["-c","developer_instructions="+json.dumps(developer,ensure_ascii=False)]
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
