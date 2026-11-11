"""Candidate-only subprocess bridge, with bounded runtime and no model transport."""
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parent

def evaluate(source,pid,mode='functional'):
    if mode not in ('functional','bounded'):raise ValueError('Unsupported offline mode')
    env=dict(os.environ,PYTHONUTF8='1',PYTHONDONTWRITEBYTECODE='1')
    # This worker has no online generation capability; do not give it model credentials.
    for name in ('DMXAPI_API_KEY','OPENAI_API_KEY','ANTHROPIC_API_KEY'):env.pop(name,None)
    process=subprocess.run([sys.executable,'-B','-X','utf8',str(ROOT/'judge_worker.py')],
        input=json.dumps(dict(source=source,pid=pid,mode=mode)),capture_output=True,text=True,encoding='utf-8',
        cwd=ROOT,env=env,timeout=50 if mode=='bounded' else 30,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
    if process.returncode:raise RuntimeError('Isolated F1.4 worker failed: '+process.stderr[-1800:])
    result=json.loads(process.stdout)
    assert result['result']['evidence_metadata']['data_version']=='STBench-F1.4'
    return result
