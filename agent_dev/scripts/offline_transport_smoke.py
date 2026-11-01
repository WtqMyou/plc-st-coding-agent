"""Actual Codex CLI -> local Responses bridge -> validated simulated Chat result."""
import argparse
import json
import sys
import tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from stbench.billing import CampaignBudget
from stbench.transport import MeteredProvider
from stbench.codex_baseline import ResponsesGateway,CodexProvider
from stbench.cli import problems,reference,config
from stbench.portability import adapt
from stbench.harness.prompts import build_system_prompt,build_task_prompt
from stbench.evaluation import atomic_json

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,default=ROOT/'evidence/campaign_transport_smoke.json')
    args=ap.parse_args()
    cfg=config('');p=next(p for p in problems() if p.pid=='self-hard-07');p,src,_=adapt(p,reference(p),'codesys')
    requests=[]
    def sender(url,payload,key,timeout):
        assert key=='offline-no-credential' and url.endswith('/chat/completions')
        requests.append(dict(model=payload['model'],roles=[m['role'] for m in payload['messages']],
                             request_bytes=len(json.dumps(payload).encode()),
                             input_utf8_upper=len(json.dumps(payload['messages'],ensure_ascii=False).encode())+4096))
        return dict(model='offline-bridge',choices=[dict(finish_reason='stop',message=dict(content='```st\n'+src+'\n```'))],
                    usage=dict(prompt_tokens=100,completion_tokens=200))
    with tempfile.TemporaryDirectory() as d:
        budget=CampaignBudget(Path(d)/'budget.json','preflight')
        transport=MeteredProvider(dict(model='offline-bridge',api_key_env='UNUSED',base_url='https://offline.invalid/v1',
            input_cny_per_million=1,output_cny_per_million=2),budget,offline=True,sender=sender,timeout=420)
        with ResponsesGateway(model='offline-bridge',provider=transport) as gateway:
            cli=CodexProvider(gateway,model='offline-bridge',mock=True,work_root=Path(cfg['platform_root'])/'builds/codex',timeout=450)
            result=cli.generate([dict(role='system',content=build_system_prompt()),dict(role='user',content=build_task_prompt(p))])
            assert 'scanSeconds' in result.text and result.usage['prompt_tokens']==100 and result.cost_cny>0
            assert len(requests)==1
            assert transport.timeout==420
            report=dict(passed=True,upstream_requests=requests,cli_requests=gateway.requests,
                actual_model=result.model,usage=result.usage,synthetic_accounted_cny=result.cost_cny,
                request_timeout_seconds=transport.timeout,
                warning='Entire upstream simulated; no live key or paid requests')
    atomic_json(args.out,report)
    print(json.dumps(report,ensure_ascii=False))

if __name__=='__main__':main()
