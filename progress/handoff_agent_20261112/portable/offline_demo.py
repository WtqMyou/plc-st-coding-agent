"""Replay actual Agent records; optional fresh local verification, never model calls."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
CASES=ROOT/'03_PPT视频素材/案例'

def judge(payload):
    env=dict(os.environ,PYTHONUTF8='1',PYTHONDONTWRITEBYTECODE='1')
    for key in list(env):
        if 'API_KEY' in key.upper() or key.upper() in ('GH_TOKEN','GITHUB_TOKEN'):env.pop(key)
    process=subprocess.run([sys.executable,'-B','-X','utf8',str(Path(__file__).with_name('judge_worker.py'))],
        input=json.dumps(payload),capture_output=True,text=True,encoding='utf-8',env=env,timeout=90,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
    if process.returncode:raise RuntimeError('Local judge failed: '+process.stderr[-1200:])
    return json.loads(process.stdout)

def replay(case,verify=False,formal=False):
    folder=CASES/case;meta=json.loads((folder/'案例.json').read_text(encoding='utf-8'))
    print('\n'+'='*64+'\n'+meta['label']+'\n真实记录回放：不调用模型、不读取API密钥。')
    print('题目：'+meta['title']+'  ['+meta['job_id']+']')
    a,z=meta['before'],meta['after']
    print('CODESYS编译：'+a['native']+' -> '+z['native'])
    print('功能用例：'+str(a['tests'])+'/'+str(meta['total'])+' -> '+str(z['tests'])+'/'+str(meta['total']))
    print('形式状态：'+a['formal']+' -> '+z['formal'])
    print('\n首轮实际反馈：\n'+(folder/'首轮反馈.txt').read_text(encoding='utf-8'))
    print('修复前后代码及原始记录：'+str(folder))
    if verify:
        for name,expected in (('before',a),('after',z)):
            # Original native-failed candidates were not function-executed in the live gate.
            if expected['native'] not in ('passed','unsupported_platform'):
                print(name+'：原生编译反馈按历史日志回放；不将新离线功能结果混成原成绩。');continue
            result=judge(dict(mode='candidate',pid=meta['pid'],code=(folder/(name+'.st')).read_text(encoding='utf-8'),formal=formal))
            assert result['passed']==expected['tests'] and result['total']==meta['total']
            print(name+'：本次离线功能复验 '+str(result['passed'])+'/'+str(result['total'])+'；形式 '+result['verification_status'])
    return meta

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case',choices=('all','native','functional','formal'),default='all')
    parser.add_argument('--verify',action='store_true',help='Fresh offline functional checks, no model calls')
    parser.add_argument('--formal-check',action='store_true',help='Also run bounded formal checks, up to 30 seconds')
    args=parser.parse_args()
    for case in ('native','functional','formal') if args.case=='all' else (args.case,):replay(case,args.verify or args.formal_check,args.formal_check)
