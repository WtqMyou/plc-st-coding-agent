"""User-authorized continuation after the frozen 80 gate, with no manual wait."""
import argparse
import copy
import ctypes
from datetime import datetime
import hashlib
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid
import psutil
import shutil
sys.path.insert(0,str(Path(__file__).resolve().parent))
import f14_rotation_study as b
from stbench.billing import ledger_lock,money
from stbench.providers.base import ProviderError

REPO=b.REPO
ID='f14_remove80_20261112'
CONFIG=REPO/'progress/f14_no80/config.json'
OUT=REPO/'progress/evidence/f14_no80_20261112'
load,sha,stamp,atomic_json,sanitize=b.load,b.sha,b.stamp,b.atomic_json,b.sanitize
MIRROR=b.MIRROR
KIND,BASELINE,HISTORY,prefix_ok=b.KIND,b.BASELINE,b.HISTORY,b.prefix_ok

def files():return [Path(__file__),Path(__file__).with_name('f14_no80_report.py'),CONFIG,CONFIG.parent/'授权与接续.md',REPO/'progress/tests/test_f14_no80.py']

def locations():
    cfg=b.config();root=Path(cfg['campaign_root'])
    return cfg,root,root/'amendments'/ID

def alive(marker):
    try:
        process=psutil.Process(marker['pid']);created=datetime.fromisoformat(marker['process_created_at']).timestamp()
        return process.is_running() and abs(process.create_time()-created)<2 and process.status()!=psutil.STATUS_ZOMBIE
    except (KeyError,ValueError,psutil.Error):return False

def prepare():
    cfg,root,amend=locations();b.verify(cfg)
    assert not amend.exists(),'Do not overwrite an amendment'
    policy=load(CONFIG);assert policy==dict(amendment_id=ID,total_cap_cny=190,primary_switch_cny=75,
        manual_pause_at_80=False,effective_review_ceiling_cny=190,automatic_retry=False,
        user_instruction='80 yuan no longer requires a pause; only switch credentials before 75')
    proc=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p','test_f14_no80.py','-q'],
        cwd=REPO,capture_output=True,text=True,encoding='utf-8',timeout=120)
    assert proc.returncode==0,proc.stderr[-1500:]
    # Do not touch the running study, its ledger, its signatures or its current Git index.
    amend.mkdir(parents=True)
    plan=dict(amendment_id=ID,policy=policy,parent_study_plan_sha256=sha(root/'study_plan.json'),
        files={p.relative_to(REPO).as_posix():sha(p) for p in files()},prepared_at=stamp(),
        initial_state=load(root/'study_state.json'),test_log=proc.stderr,paid_requests_during_preparation=0)
    atomic_json(amend/'amendment_plan.json',plan);atomic_json(amend/'state.json',dict(state='prepared',at=stamp()))
    OUT.mkdir(parents=True,exist_ok=False);atomic_json(OUT/'amendment_plan.json',plan)
    atomic_json(OUT/'state.json',load(amend/'state.json'))
    print('PREPARED no-80 amendment; frozen live runner untouched',flush=True)

def verify():
    cfg,root,amend=locations();b.verify(cfg);plan=load(amend/'amendment_plan.json')
    assert plan['files']=={p.relative_to(REPO).as_posix():sha(p) for p in files()}
    assert plan['parent_study_plan_sha256']==sha(root/'study_plan.json')
    return cfg,root,amend,plan

def ready(state,marker):
    if state['state']=='completed':return 'completed'
    if state['state']=='stopped':return 'fault'
    if state['state']=='paused_for_api_review' and not alive(marker):return 'activate'
    if state['state']=='running' and not alive(marker):return 'fault'
    return 'wait'

def authorize(path,before_bytes,parent_sha,amendment_sha):
    path=Path(path);before=json.loads(before_bytes)
    with ledger_lock(path):
        state=load(path)
        assert path.read_bytes()==before_bytes and state['limit_cny']==190 and not state.get('halted')
        old=state.get('f14_rotation_authorization',{})
        assert old.get('study_plan_sha256')==parent_sha and old.get('review_pause_cny')==80
        assert all(e['status']=='settled' for e in state['events'][HISTORY:]),'New unknown fees forbid automatic continuation'
        approval=dict(amendment_id=ID,parent_plan_sha256=parent_sha,amendment_plan_sha256=amendment_sha,
            total_cap_cny=190,review_ceiling_cny=190,manual_pause_at_80=False,primary_switch_cny=75,
            event_count_before=len(state['events']),spent_cny_before=state['spent_cny'],authorized_at=stamp(),
            authorization='Explicit user instruction on 2026-11-12: remove 80 pause, retain switch before 75 and total 190 cap')
        assert 'f14_no80_authorization' not in state,'Existing amendment must not be overwritten'
        state['f14_no80_authorization']=approval
        assert prefix_ok(state,before) and state['spent_cny']==before['spent_cny']
        atomic_json(path,state)
    return approval

class Budget(b.StudyBudget):
    def __init__(self,path,parent_sha,amendment_sha,slot):
        super().__init__(path,parent_sha,slot);self.amendment_sha=amendment_sha
        approval=self.read().get('f14_no80_authorization',{})
        if (approval.get('amendment_plan_sha256'),approval.get('review_ceiling_cny'),approval.get('manual_pause_at_80'))!=(amendment_sha,190,False):
            raise ProviderError('Missing explicit no-80 amendment authorization')
    def admit_job(self,upper):
        state=self.snapshot();projected=money(state['spent_cny'])+money(upper)
        if projected>money(190):raise ProviderError('190 CNY total cap; no job started')
        if self.active_batch=='primary' and projected>money(75):raise b.KeySwitch('Switch before primary job could cross 75')
    def reserve(self,amount,*,request=None):
        amount=money(amount)
        with ledger_lock(self.path):
            state=self.read();projected=money(state['spent_cny'])+amount
            if self.active_batch=='primary' and projected>money(75):raise b.KeySwitch('Primary 75 guard before send')
            if projected+money(self.protected_cny)>money(190):raise ProviderError('190 CNY total and pending-coverage guard')
            context=dict(self.context,study_kind=KIND,credential_batch=self.active_batch,execution_amendment_sha256=self.amendment_sha)
            if context.get('candidate_index') not in (0,1) or not context.get('job_id'):raise ProviderError('Invalid candidate identity')
            new=[e for e in state['events'] if e.get('phase')==KIND]
            if len(new)>=280 or any(e['request']['job_id']==context['job_id'] and e['request']['candidate_index']==context['candidate_index'] for e in new):
                raise ProviderError('Duplicate candidate or request cap')
            state['spent_cny']=float(projected)
            state['events'].append(dict(request_id=uuid.uuid4().hex,phase=KIND,status='reserved',reserved_cny=float(amount),
                created_at=time.time(),phase_ceiling_cny=190,review_checkpoint_cny=190,manual_pause_at_80=False,
                primary_switch_checkpoint_cny=75,request=dict(request or {},**context)))
            atomic_json(self.path,state);return len(state['events'])-1

def publish_sources(cfg,root,amend):
    assert not subprocess.check_output(['git','diff','--cached','--name-only'],cwd=REPO),'Unrelated staged work'
    atomic_json(OUT/'state.json',load(amend/'state.json'))
    evidence=MIRROR/'execution_amendments'/ID;evidence.mkdir(parents=True,exist_ok=True)
    for name in ('amendment_plan.json','authorization.json','state.json'):
        if (amend/name).is_file():shutil.copyfile(amend/name,evidence/name)
    targets=[p.relative_to(REPO).as_posix() for p in files()]+['progress/f14_no80/README.md',OUT.relative_to(REPO).as_posix(),MIRROR.relative_to(REPO).as_posix()]
    subprocess.run(['git','add','--',*targets],cwd=REPO,check=True,capture_output=True)
    if subprocess.run(['git','diff','--cached','--quiet'],cwd=REPO).returncode:
        subprocess.run(['git','commit','-q','-m','feat: activate explicit no-80 experiment continuation'],cwd=REPO,check=True,capture_output=True)
    env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
    subprocess.run(['git','-c','http.version=HTTP/1.1','-c','http.lowSpeedLimit=1000','-c','http.lowSpeedTime=30','push','origin','main'],
        cwd=REPO,env=env,check=True,capture_output=True,timeout=60)
    b.base.old.ensure_pushed()

def activate():
    from f14_no80_report import report
    cfg,root,amend,policy=verify();state=load(root/'study_state.json')
    assert ready(state,load(root/'active_run.json'))=='activate','Activate only at a clean, terminated 80 boundary'
    b.base.old.old.support.no_other_runner(cfg)
    assert sha(cfg['budget_ledger_path'])==load(root/'ledger_checkpoint.json')['sha256']
    parent=load(root/'study_plan.json');b.history(cfg,root,parent);pending=b.base.remaining(root,parent)
    before=Path(cfg['budget_ledger_path']).read_bytes();assert not json.loads(before).get('halted')
    assert b.credentials.load_credentials(cfg)==load(root/'credential_bindings.private.json')
    slot=load(root/'current_credential_batch.json')['slot'];catalog=b.credentials.catalog(cfg,slot)
    (amend/'ledger_before_amendment.private.json').write_bytes(before)
    atomic_json(amend/'state.json',dict(state='ready_to_activate',at=stamp(),remaining=len(pending)))
    publish_sources(cfg,root,amend)  # Freeze and push the new code before any new paid request.
    approval=authorize(cfg['budget_ledger_path'],before,sha(root/'study_plan.json'),sha(amend/'amendment_plan.json'))
    atomic_json(amend/'authorization.json',approval);atomic_json(OUT/'authorization.json',approval)
    atomic_json(amend/'state.json',dict(state='activated',at=stamp(),catalog=catalog))
    atomic_json(root/'execution_amendment.json',dict(amendment_id=ID,amendment_plan_sha256=sha(amend/'amendment_plan.json'),manual_pause_at_80=False,total_cap_cny=190,primary_switch_cny=75))
    budget=Budget(cfg['budget_ledger_path'],sha(root/'study_plan.json'),sha(amend/'amendment_plan.json'),slot)
    final='stopped';current_job=None;awake=False
    atomic_json(root/'active_run.json',dict(**b.base.old.old.support.current_process_marker(),state='running',entry='f14_no80.py'))
    try:
        atomic_json(root/'study_state.json',dict(state='running',at=stamp(),execution_amendment=ID,reason='Explicit user no-80 continuation'))
        b.base.checkpoint(cfg,root);report(cfg,parent);publish_sources(cfg,root,amend)
        if os.name=='nt':awake=bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
        for job in parent['jobs']:
            if job['job_id'] not in pending:continue
            current_job=job;verify();assert sha(cfg['budget_ledger_path'])==load(root/'ledger_checkpoint.json')['sha256']
            b.history(cfg,root,parent)
            try:budget.admit_job(pending[job['job_id']])
            except b.KeySwitch:
                catalog=b.credentials.catalog(cfg,'secondary');b.bind_batch(cfg,root,parent,'secondary',catalog,pending)
                budget.active_batch='secondary';report(cfg,parent);publish_sources(cfg,root,amend);budget.admit_job(pending[job['job_id']])
            atomic_json(root/'study_state.json',dict(state='running',at=stamp(),current_job=job['job_id'],credential_batch=budget.active_batch,execution_amendment=ID))
            report(cfg,parent)
            record=b.base.generate_job(cfg,root,parent,job,budget,pending,factory=b.credentials.provider_factory)
            assert record['job_done'];record.update(credential_batch=budget.active_batch,execution_amendment=ID)
            atomic_json(root/'jobs'/job['condition']/(job['pid']+'.json'),record)
            snapshot=b.history(cfg,root,parent);assert snapshot['events'][-1]['status']=='settled'
            pending.pop(job['job_id']);b.base.checkpoint(cfg,root);summary=report(cfg,parent);publish_sources(cfg,root,amend)
            print('FINISHED',job['job_id'],summary['recorded'],'/140',snapshot['spent_cny'],'CNY; no manual 80 pause',flush=True)
        else:
            atomic_json(root/'final_audit.json',b.audit_final(cfg,root,parent));final='completed'
            atomic_json(root/'study_state.json',dict(state='completed',at=stamp(),execution_amendment=ID))
            snapshot=load(cfg['budget_ledger_path'])
            atomic_json(root/'completion.json',dict(completed=True,recorded=140,requests=len(snapshot['events'])-HISTORY,total_accounted_cny=snapshot['spent_cny'],ended_at=stamp()))
    except BaseException as exc:
        if current_job:
            path=root/'jobs'/current_job['condition']/(current_job['pid']+'.json');record=load(path)
            if record:record.update(credential_batch=budget.active_batch,execution_amendment=ID);atomic_json(path,record)
        atomic_json(root/'study_state.json',dict(state='stopped',at=stamp(),error=sanitize(type(exc).__name__+': '+str(exc)),execution_amendment=ID));raise
    finally:
        if awake:ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        marker=load(root/'active_run.json');marker.update(state=final,ended_at=stamp());atomic_json(root/'active_run.json',marker)
        b.base.checkpoint(cfg,root);report(cfg,parent);publish_sources(cfg,root,amend)

def _watch():
    cfg,root,amend,plan=verify()
    previous=load(amend/'watcher.json');assert not alive(previous),'No duplicate amendment watcher'
    atomic_json(amend/'watcher.json',dict(**b.base.old.old.support.current_process_marker(),state='watching',at=stamp()))
    atomic_json(amend/'state.json',dict(state='watching',at=stamp(),manual_pause_at_80=False,primary_switch_cny=75,total_cap_cny=190))
    try:
        while True:
            state=load(root/'study_state.json');decision=ready(state,load(root/'active_run.json'))
            if decision=='activate':activate();break
            if decision in ('completed','fault'):
                atomic_json(amend/'state.json',dict(state='not_needed_completed' if decision=='completed' else 'stopped_on_parent_fault',at=stamp(),parent_state=state))
                print('NO EXTRA CALLS',decision,flush=True);break
            time.sleep(2)
    finally:
        marker=load(amend/'watcher.json');marker.update(state='ended',at=stamp());atomic_json(amend/'watcher.json',marker)

def watch():
    _,_,amend,_=verify()
    assert not alive(load(amend/'watcher.json')),'No duplicate amendment watcher'
    with ledger_lock(amend/'watcher_singleton.json'):_watch()

def serve(port):
    cfg,root,amend,_=verify()
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            name=self.path.split('?',1)[0].lstrip('/') or 'status.html'
            if name not in ('status.html','status.json'):self.send_error(404);return
            if name.endswith('.json'):
                data=load(root/name);data.update(manual_pause_at_80=False,total_cap_cny=190,primary_switch_cny=75,execution_amendment_state=load(amend/'state.json'))
                body=json.dumps(data,ensure_ascii=False).encode()
            else:
                page=(root/name).read_text(encoding='utf-8')
                banner='<section style="padding:16px;background:#e8f6ed;border:1px solid #a8d2b7"><b>最新授权：取消80元人工暂停；75元前自动切换密钥，累计上限190元。</b><p>当前冻结进程按原边界运行，接续入口会自动接管，无需人工确认；旧表中的80元为原方案记录。</p></section>'
                body=(banner+page).encode()
            self.send_response(200);self.send_header('Content-Type','application/json; charset=utf-8' if name.endswith('.json') else 'text/html; charset=utf-8')
            self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
        def log_message(self,*args):pass
    ThreadingHTTPServer(('127.0.0.1',port),Handler).serve_forever()

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('command',choices=('prepare','watch','check','serve'));parser.add_argument('--port',type=int,default=8885)
    args=parser.parse_args()
    if args.command=='prepare':prepare()
    elif args.command=='check':verify();print('PASS signed no-80 amendment')
    elif args.command=='serve':serve(args.port)
    else:watch()
