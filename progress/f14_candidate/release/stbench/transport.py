"""Validated Chat/Responses transports with shared billing, no implicit retry/fallback."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request
from .providers.base import ProviderError, ProviderResponse

class HTTPFailure(ProviderError):
    def __init__(self,status):
        self.status=status
        super().__init__("Upstream HTTP "+str(status))

class IdentityFailure(ProviderError):
    pass

class RequestDeadline(ProviderError):
    pass

def post_direct(url, payload, key, timeout):
    request=urllib.request.Request(url,data=json.dumps(payload).encode(),method="POST",
        headers={"Content-Type":"application/json","Authorization":"Bearer "+key})
    try:
        with urllib.request.urlopen(request,timeout=timeout) as response:
            body=response.read();kind=response.headers.get("Content-Type","")
        if "text/event-stream" in kind:
            completed=None
            for line in body.decode().splitlines():
                if not line.startswith("data:"):continue
                text=line[5:].strip()
                if text=="[DONE]":continue
                event=json.loads(text)
                if event.get("type") in ("error","response.failed"):
                    raise ProviderError("Responses upstream incomplete/error")
                if event.get("type") in ("response.completed","response.incomplete"):completed=event["response"]
            if completed is None:raise ProviderError("Missing completed Responses event")
            return completed
        return json.loads(body)
    except urllib.error.HTTPError as error:
        raise HTTPFailure(error.code) from None
    except (OSError,ValueError,KeyError,TimeoutError) as error:
        raise ProviderError("Upstream "+type(error).__name__+"; no automatic retry") from None

def post(url,payload,key,timeout):
    """Bound the entire HTTP exchange, including streams that keep sending heartbeats."""
    job=dict(url=url,payload=payload,key=key,timeout=timeout)
    allowed={'PATH','SYSTEMROOT','WINDIR','COMSPEC','PATHEXT','TEMP','TMP','USERPROFILE','APPDATA',
             'LOCALAPPDATA','PROGRAMDATA','PROCESSOR_ARCHITECTURE','HOMEDRIVE','HOMEPATH',
             'HTTPS_PROXY','HTTP_PROXY','ALL_PROXY','NO_PROXY','SSL_CERT_FILE','SSL_CERT_DIR'}
    env={k:v for k,v in os.environ.items() if k.upper() in allowed}
    try:
        result=subprocess.run([sys.executable,'-B','-X','utf8','-m','stbench.transport_worker'],
            cwd=Path(__file__).resolve().parents[1],input=json.dumps(job),capture_output=True,
            text=True,encoding='utf-8',env=env,timeout=max(.01,timeout))
    except subprocess.TimeoutExpired:
        raise RequestDeadline('Upstream wall deadline exceeded; no automatic retry') from None
    try:envelope=json.loads(result.stdout)
    except ValueError:raise ProviderError('Upstream worker invalid result; no automatic retry') from None
    if envelope.get('ok') is True and result.returncode==0:return envelope['data']
    if isinstance(envelope.get('http_status'),int):raise HTTPFailure(envelope['http_status'])
    raise ProviderError(envelope.get('error','Upstream worker failed; no automatic retry'))

def validate_response(data, protocol, accepted):
    model=data.get("model")
    if not isinstance(model,str) or model.casefold() not in {x.casefold() for x in accepted}:
        raise IdentityFailure("Missing/unapproved actual model identity")
    usage=data.get("usage")
    if not isinstance(usage,dict):raise ProviderError("Missing usage")
    keys=("input_tokens","output_tokens") if protocol=="responses" else ("prompt_tokens","completion_tokens")
    for k in keys:
        if isinstance(usage.get(k),bool) or not isinstance(usage.get(k),int) or usage[k]<0:
            raise ProviderError("Missing/invalid token usage")
    if protocol=="responses":
        complete=data.get("status")=="completed"
        text="".join(c.get("text","") for item in data.get("output",[]) if item.get("type")=="message"
            for c in item.get("content",[]) if c.get("type")=="output_text")
        finish=data.get("status","")
    else:
        choices=data.get("choices") or []
        if len(choices)!=1:raise ProviderError("Expected one Chat completion")
        finish=choices[0].get("finish_reason")
        text=(choices[0].get("message") or {}).get("content") or ""
        complete=finish=="stop"
    if not isinstance(text,str):raise ProviderError("Non-text completion")
    return dict(model=model,text=text,prompt_tokens=usage[keys[0]],completion_tokens=usage[keys[1]],
                complete=complete and bool(text.strip()),finish_reason=finish,usage=usage)

class MeteredProvider:
    name="openai-compat"
    def __init__(self,spec,budget,*,max_tokens=16384,protocol="chat",timeout=180,sender=None,offline=False):
        self.spec,self.budget,self.model=spec,budget,spec["model"]
        self.max_tokens,self.protocol,self.timeout=max_tokens,protocol,timeout
        self.sender=sender or post;self.offline=offline;self.last_receipt={}
        self.last_charge=0.;self.before_send=None
        self.response_observer=None
        self.probe_rejection_allowed=False
        if offline:self.name="mock"
    def upper(self,messages):
        payload_bytes=len(json.dumps(messages,ensure_ascii=False).encode())+4096
        return (payload_bytes*self.spec["input_cny_per_million"]+
                self.max_tokens*self.spec["output_cny_per_million"])/1e6
    def generate(self,messages):
        started=time.monotonic();self.last_charge=0.;self.last_receipt={}
        if self.before_send:self.before_send(messages)
        if not self.offline:
            key=os.environ.get(self.spec["api_key_env"],"")
            if not key:raise ProviderError("Missing configured credential environment variable")
        else:key="offline-no-credential"
        index=self.budget.reserve(self.upper(messages),request=dict(model=self.model,protocol=self.protocol,
            timeout_seconds=self.timeout,max_output_tokens=self.max_tokens))
        if self.protocol=="responses":
            payload=dict(model=self.model,input=messages,max_output_tokens=self.max_tokens,stream=True,store=False)
            endpoint=self.spec.get("responses_base_url",self.spec["base_url"])+"/responses"
        else:
            payload=dict(model=self.model,messages=messages,max_tokens=self.max_tokens,stream=False)
            endpoint=self.spec["base_url"].rstrip("/")+"/chat/completions"
        # Both frameworks share this exact per-model parameter map.
        payload.update(self.spec.get("parameters",{}))
        try:
            data=self.sender(endpoint,payload,key,self.timeout)
            v=validate_response(data,self.protocol,self.spec.get("accepted_models",[self.model]))
            cost=(v["prompt_tokens"]*self.spec["input_cny_per_million"]+
                  v["completion_tokens"]*self.spec["output_cny_per_million"])/1e6
            receipt={k:v[k] for k in ("model","prompt_tokens","completion_tokens","finish_reason")}
            receipt.update(basis="Public-price upper estimate; no cache discounts assumed",protocol=self.protocol,
                           usage=v['usage'],requested_max_output_tokens=self.max_tokens)
            # Preserve known usage even if settlement discovers a violated reservation.
            self.last_charge=cost;self.last_receipt=receipt
            self.budget.settle(index,cost,metadata=receipt)
            if self.response_observer is not None:
                self.response_observer(data,self.protocol)
            if v['completion_tokens']>self.max_tokens:
                self.budget.halt('Output token limit exceeded',details=dict(category='output_limit',
                    model=self.model,protocol=self.protocol,event_index=index))
                raise ProviderError('Upstream exceeded requested output token limit')
            if not v["complete"]:
                raise ProviderError("Generation incomplete/empty: "+str(v["finish_reason"]))
            response=ProviderResponse(text=v["text"],model=v["model"],usage={k:v[k] for k in
                ("prompt_tokens","completion_tokens")},latency_s=time.monotonic()-started)
            response.cost_cny=cost
            return response
        except HTTPFailure as error:
            if self.probe_rejection_allowed and self.protocol=="responses" and error.status in (400,404,405,422):
                self.last_receipt={"protocol_rejected":error.status,"reserved_retained":True}
            else:self.budget.halt("HTTP failure; reservation retained")
            raise
        except ProviderError as error:
            if not self.last_receipt:
                self.budget.halt("Unconfirmed upstream result; reservation retained",details=dict(
                    category=('model_identity' if isinstance(error,IdentityFailure) else
                              'request_timeout' if isinstance(error,RequestDeadline) else 'upstream_unconfirmed'),
                    model=self.model,protocol=self.protocol,event_index=index))
            raise
        except Exception as error:
            self.budget.halt("Malformed upstream result; reservation retained")
            raise ProviderError("Upstream validation "+type(error).__name__) from None

def responses_messages(job):
    """Read-only code-generation subset; reject stateful/tool/binary inputs explicitly."""
    if job.get("previous_response_id"):raise ProviderError("Stateless baseline cannot consume previous_response_id")
    result=[]
    if job.get("instructions"):result.append(dict(role="system",content=job["instructions"]))
    items=job.get("input",[])
    if isinstance(items,str):items=[dict(role="user",content=items)]
    if not isinstance(items,list):raise ProviderError("Invalid Responses input")
    for item in items:
        if item.get("type","message")!="message" or item.get("role") not in ("system","developer","user","assistant"):
            raise ProviderError("Unsupported Responses item")
        content=item.get("content","")
        if isinstance(content,list):
            if any(c.get("type") not in ("input_text","output_text") for c in content):
                raise ProviderError("Only text content is supported")
            content="\n".join(c.get("text","") for c in content)
        if not isinstance(content,str):raise ProviderError("Invalid message content")
        result.append(dict(role="system" if item["role"]=="developer" else item["role"],content=content))
    return result
