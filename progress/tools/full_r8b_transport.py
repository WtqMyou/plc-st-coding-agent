"""Versioned HTTP adapter: incremental terminal-event parsing, private raw traces, no retries."""
import hashlib
import http.client
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import urllib.request
import urllib.error
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'agent_dev_r9_stage3'))
from stbench.providers.base import ProviderError
from stbench.transport import MeteredProvider as LegacyMetered,HTTPFailure,RequestDeadline
from stbench.evaluation import atomic_json

class ProtocolFailure(ProviderError):
    pass

MAX_BODY=16*1024*1024
ENV_ALLOW={'PATH','SYSTEMROOT','WINDIR','COMSPEC','PATHEXT','TEMP','TMP','USERPROFILE','APPDATA',
           'LOCALAPPDATA','PROGRAMDATA','PROCESSOR_ARCHITECTURE','HOMEDRIVE','HOMEPATH',
           'HTTPS_PROXY','HTTP_PROXY','ALL_PROXY','NO_PROXY','SSL_CERT_FILE','SSL_CERT_DIR'}

def exchange(url,payload,key,timeout,directory):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
    body_path=directory/'http_body.bin';diag_path=directory/'diagnostic.json'
    if body_path.exists() or diag_path.exists():raise ProtocolFailure('Existing HTTP trace; no implicit retry')
    diagnostic=dict(adapter='full-r8b-http-v1',started_at=time.time(),bytes_received=0,event_count=0,
                    ignored_non_object_events=0,completed_terminal=False,automatic_retries=0)
    started=time.monotonic()
    def finish(**extra):
        diagnostic.update(extra,elapsed_s=round(time.monotonic()-started,6))
        diagnostic['raw_body_sha256']=hashlib.sha256(body_path.read_bytes()).hexdigest() if body_path.exists() else None
        atomic_json(diag_path,diagnostic)
    request=urllib.request.Request(url,data=json.dumps(payload).encode(),method='POST',
                headers={'Content-Type':'application/json','Authorization':'Bearer '+key})
    with body_path.open('xb') as raw:
        def retain(chunk):
            if chunk:
                raw.write(chunk);raw.flush();diagnostic['bytes_received']+=len(chunk)
                if diagnostic['bytes_received']>MAX_BODY:raise ProtocolFailure('HTTP response exceeds local capture limit')
        def event(data_lines):
            if not data_lines:return None
            text='\n'.join(data_lines).strip()
            if not text:return None
            if text=='[DONE]':raise ProtocolFailure('SSE done without a completed response object')
            try:item=json.loads(text)
            except (ValueError,UnicodeError) as exc:raise ProtocolFailure('Malformed SSE JSON: '+type(exc).__name__) from None
            diagnostic['event_count']+=1
            if not isinstance(item,dict):
                diagnostic['ignored_non_object_events']+=1
                return None
            kind=item.get('type')
            if kind in ('error','response.failed'):raise ProtocolFailure('Upstream explicit error event')
            if kind in ('response.completed','response.incomplete'):
                result=item.get('response')
                if not isinstance(result,dict):raise ProtocolFailure('Terminal SSE event lacks response object')
                diagnostic['completed_terminal']=True
                diagnostic['terminal_event_type']=kind
                return result
            return None
        try:
            with urllib.request.urlopen(request,timeout=timeout) as reply:
                diagnostic['http_status']=getattr(reply,'status',200)
                diagnostic['content_type']=reply.headers.get('Content-Type','')
                if 'text/event-stream' in diagnostic['content_type'].lower():
                    pending=[]
                    while True:
                        try:line=reply.readline()
                        except http.client.IncompleteRead as exc:
                            retain(exc.partial)
                            raise
                        if not line:
                            result=event(pending)
                            if result is not None:
                                finish(outcome='completed_response');return result
                            raise ProtocolFailure('SSE EOF before completed response')
                        retain(line)
                        try:text=line.decode('utf-8').rstrip('\r\n')
                        except UnicodeError as exc:raise ProtocolFailure('Invalid SSE encoding: '+type(exc).__name__) from None
                        if not text:
                            result=event(pending);pending=[]
                            if result is not None:
                                finish(outcome='completed_response');return result
                        elif text.startswith('data:'):
                            value=text[5:].lstrip(' ')
                            # Some compatible services omit blank event separators.
                            # Flush only a complete JSON value, preserving multiline JSON.
                            if pending:
                                try:json.loads('\n'.join(pending));complete=True
                                except ValueError:complete=False
                                if complete:
                                    result=event(pending);pending=[]
                                    if result is not None:
                                        finish(outcome='completed_response');return result
                            pending.append(value)
                            try:parsed=json.loads('\n'.join(pending))
                            except ValueError:parsed=None
                            if isinstance(parsed,dict) and parsed.get('type') in ('response.completed','response.incomplete','error','response.failed'):
                                result=event(pending);pending=[]
                                if result is not None:
                                    finish(outcome='completed_response');return result
                        # Comments, event labels and blank heartbeat frames do not complete a request.
                else:
                    while True:
                        try:chunk=reply.read(65536)
                        except http.client.IncompleteRead as exc:
                            retain(exc.partial);raise
                        if not chunk:break
                        retain(chunk)
                    try:result=json.loads(body_path.read_bytes().decode('utf-8'))
                    except (ValueError,UnicodeError) as exc:raise ProtocolFailure('Malformed JSON body: '+type(exc).__name__) from None
                    if not isinstance(result,dict):raise ProtocolFailure('Non-object JSON response')
                    finish(outcome='json_response');return result
        except urllib.error.HTTPError as exc:
            diagnostic['http_status']=exc.code
            try:retain(exc.read(MAX_BODY))
            except Exception:pass
            finish(outcome='http_error',exception_type=type(exc).__name__)
            raise HTTPFailure(exc.code) from None
        except Exception as exc:
            finish(outcome='transport_error',exception_type=type(exc).__name__,
                   error_category=str(exc) if isinstance(exc,ProtocolFailure) else 'HTTP exchange failed')
            if isinstance(exc,ProviderError):raise
            raise ProviderError('Upstream '+type(exc).__name__+'; raw trace retained; no automatic retry') from None

def post(url,payload,key,timeout,directory):
    directory=Path(directory)
    job=dict(url=url,payload=payload,key=key,timeout=timeout,directory=str(directory))
    env={k:v for k,v in os.environ.items() if k.upper() in ENV_ALLOW}
    try:
        proc=subprocess.run([sys.executable,'-B','-X','utf8',str(Path(__file__).with_name('full_r8b_http_worker.py'))],
                    input=json.dumps(job),capture_output=True,text=True,encoding='utf-8',env=env,timeout=max(.01,timeout))
    except subprocess.TimeoutExpired:
        directory.mkdir(parents=True,exist_ok=True);diag=directory/'diagnostic.json'
        existing=json.loads(diag.read_text('utf-8')) if diag.exists() else {}
        body=directory/'http_body.bin'
        existing.update(outcome='wall_deadline',exception_type='RequestDeadline',automatic_retries=0,
                        bytes_received=body.stat().st_size if body.exists() else 0,
                        raw_body_sha256=hashlib.sha256(body.read_bytes()).hexdigest() if body.exists() else None)
        atomic_json(diag,existing)
        raise RequestDeadline('Upstream total wall deadline exceeded; partial trace retained; no automatic retry') from None
    directory.mkdir(parents=True,exist_ok=True)
    (directory/'worker_result.json').write_bytes(proc.stdout.encode())
    if proc.stderr:(directory/'worker.stderr.log').write_bytes(proc.stderr.encode())
    diag=directory/'diagnostic.json'
    metadata=json.loads(diag.read_text('utf-8')) if diag.exists() else {}
    metadata.update(worker_returncode=proc.returncode,worker_stderr_sha256=hashlib.sha256(proc.stderr.encode()).hexdigest())
    atomic_json(diag,metadata)
    try:result=json.loads(proc.stdout)
    except ValueError:
        raise ProviderError('HTTP worker returned invalid IPC JSON; no automatic retry') from None
    if result.get('ok') is True and proc.returncode==0:return result['data']
    if isinstance(result.get('http_status'),int):raise HTTPFailure(result['http_status'])
    raise ProviderError(result.get('error','HTTP worker failed; no automatic retry'))

class MeteredProvider(LegacyMetered):
    def __init__(self,*args,**kwargs):
        custom_sender=kwargs.get('sender')
        offline=kwargs.get('offline',False)
        super().__init__(*args,**kwargs)
        self.diagnostic_dir=None
        if custom_sender is None and not offline:self.sender=self._send
    def _send(self,url,payload,key,timeout):
        if self.diagnostic_dir is None:raise ProviderError('Missing private HTTP evidence directory')
        return post(url,payload,key,timeout,self.diagnostic_dir)
