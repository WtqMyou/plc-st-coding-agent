"""One bounded diagnosis after a guarded identity failure; retains all prior reservations.

Only returns model/usage/finish metadata. Never logs text, keys or HTTP bodies.
"""
import json
import sys
import time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from stbench.campaign import configuration,credentials
from stbench.billing import canonical_ledger,ledger_lock,money
from stbench.evaluation import atomic_json
from stbench.transport import post
from stbench.providers.base import ProviderError

def main():
    import os
    cfg=configuration('');credentials(cfg);path=canonical_ledger(cfg)
    spec=next(s for s in cfg['models'] if not (Path(cfg['campaign_root'])/(s['id']+'_protocol.json')).exists())
    payload=dict(model=spec['model'],messages=[dict(role='user',content='Reply exactly OK.')],max_tokens=512,stream=False)
    upper=((len(json.dumps(payload).encode())+4096)*spec['input_cny_per_million']+512*spec['output_cny_per_million'])/1e6
    with ledger_lock(path):
        state=json.loads(path.read_text(encoding='utf-8'))
        audited=state.get('identity_audit_models',['deepseek-v4-pro-0813'] if state.get('identity_audit_started') else [])
        if spec['model'] in audited:raise ProviderError('This model identity audit already used; no duplicate paid request')
        if money(state['spent_cny'])+money(upper)>5:raise ProviderError('Preflight allocation exhausted')
        state['identity_audit_started']=True
        state['identity_audit_models']=audited+[spec['model']]
        state['spent_cny']=float(money(state['spent_cny'])+money(upper))
        state['events'].append(dict(phase='preflight',status='reserved',reserved_cny=upper,
            purpose='one bounded identity diagnosis',model=spec['model'],created_at=time.time()))
        atomic_json(path,state)
    data=post(spec['base_url']+'/chat/completions',payload,os.environ['DMXAPI_API_KEY'],60)
    model=data.get('model')
    safe_model=model if isinstance(model,str) and len(model)<150 and not model.startswith('sk-') else None
    usage=data.get('usage') if isinstance(data.get('usage'),dict) else {}
    usage={k:v for k,v in usage.items() if isinstance(v,int) and not isinstance(v,bool) and v>=0}
    result=dict(requested_model=spec['model'],observed_model=safe_model,usage=usage,
                finish_reason=(data.get('choices') or [{}])[0].get('finish_reason'),response_keys=sorted(data))
    out=Path(cfg['campaign_root'])/(spec['id']+'_identity_audit.json');atomic_json(out,result)
    # Keep the original mismatched-result reservation; only settle this diagnosed request.
    if safe_model and safe_model.casefold()==spec['model'].casefold() and all(k in usage for k in ('prompt_tokens','completion_tokens')):
        cost=(usage['prompt_tokens']*spec['input_cny_per_million']+usage['completion_tokens']*spec['output_cny_per_million'])/1e6
        with ledger_lock(path):
            state=json.loads(path.read_text(encoding='utf-8'));event=state['events'][-1]
            state['spent_cny']=float(money(state['spent_cny'])-money(event['reserved_cny'])+money(cost))
            event.update(status='settled',accounted_cny=cost,metadata=result)
            atomic_json(path,state)
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':main()
