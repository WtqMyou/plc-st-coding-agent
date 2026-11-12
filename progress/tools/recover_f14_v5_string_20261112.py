"""Finish an already-paid batch from immutable responses; never call a generation provider."""
from concurrent.futures import ThreadPoolExecutor,as_completed
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
import zipfile
import f14_v5_core as s
import f14_v5_report as reporting
from stbench.billing import ledger_lock

TAG='string_byte_20261112'
EXT=s.REPO/'progress/f14_v5_string_recovery'
ROOT=Path(s.config()['campaign_root'])
PRIVATE=ROOT/'operational_restarts'/TAG
PUBLIC=s.MIRROR/'operational_restarts'/TAG
NATIVE_PROBE=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_v5_string_probe_20261112_v2')
FORMAL=threading.Semaphore(2)
NATIVE=threading.Lock()
RAW_LOAD=s.load


def worker(code,pid,mode):
    env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',PYTHONUTF8='1')
    for key in ('DMXAPI_API_KEY','F14_DMXAPI_SECONDARY_KEY','OPENAI_API_KEY','ANTHROPIC_API_KEY'):env.pop(key,None)
    p=subprocess.run([sys.executable,'-B','-X','utf8',str(EXT/'judge_worker.py')],
        input=json.dumps(dict(source=code,pid=pid,mode=mode,seconds=30)),
        capture_output=True,text=True,encoding='utf-8',env=env,timeout=38 if mode=='bounded' else 30)
    assert p.returncode==0,s.sanitize(p.stderr[-2000:])
    return json.loads(p.stdout)


def response_text(response):
    raw=response['raw_response']
    if response['protocol']=='chat':return raw['choices'][0]['message'].get('content','')
    return '\n'.join(c.get('text','') for output in raw.get('output',[]) if output.get('type')=='message'
                     for c in output.get('content',[]) if c.get('type')=='output_text')


def reconstruct(job,event):
    idx=event['request']['candidate_index'];folder=ROOT/'jobs'/job['condition'];stem=job['pid']+f'.{{}}_{idx+1:02}'
    raw=(folder/(stem.format('raw_candidate')+'.st')).read_bytes().decode()
    code=(folder/(stem.format('candidate')+'.st')).read_bytes().decode()
    normalized,edits=s.normalize(raw);assert normalized==code
    response=RAW_LOAD(folder/(stem.format('response')+'.json'))
    assert s.extract_code(response_text(response))==raw
    metadata=event['metadata'];diagnostic=RAW_LOAD(folder/(stem.format('transport')+'.json'))
    return dict(idx=idx,code=code,code_hash=hashlib.sha256(code.encode()).hexdigest(),judge={},
        actual_model=metadata['model'],prompt_tokens=metadata['prompt_tokens'],completion_tokens=metadata['completion_tokens'],
        cost_cny=event['accounted_cny'],provider_error='',format_edits=edits,raw_source_sha256=hashlib.sha256(raw.encode()).hexdigest(),
        latency_s=diagnostic.get('elapsed_s',0),generation_seconds=diagnostic.get('elapsed_s',0),
        engineering_contract=s.compliance(code),reconstructed_from_settled_response=True)


def evaluate_attempt(job,original):
    result=copy.deepcopy(original);result['judge_amendment']=TAG
    if not original.get('code'):return result
    code=original['code'];digest=hashlib.sha256(code.encode()).hexdigest()
    assert digest==original['code_hash']
    native=copy.deepcopy(original.get('judge',{}).get('platform_results',{}).get('codesys',{}))
    if not native:
        with NATIVE:
            backend=s.old.old.support.CodesysBackend(s.config());backend.timeout=120
            native=backend.compile(code,type('Task',(),dict(pid=job['pid']))()).to_dict()
        assert native['status'] in ('passed','failed'),native
        s.atomic_json(PRIVATE/'reconstructed_native.json',native)
    if native.get('status')=='not_run':return result
    assert native.get('source_sha256')==digest,'Native evidence does not match the original candidate'
    if native['status']!='passed':return result
    static=worker(code,job['pid'],'static')
    if not static['result']['compiles']:
        # Preserve the established interface versus unsupported-syntax classification.
        assert not original.get('reconstructed_from_settled_response'),static
        return result
    evaluated=worker(code,job['pid'],'functional')
    r=evaluated['result']
    if r['compiles'] and r['tests_passed']==r['tests_total'] and evaluated['verification_status']!='inconclusive':
        with FORMAL:evaluated=worker(code,job['pid'],'bounded')
    evaluated['result']['platform_results']={'codesys':native}
    evaluated['result']['evidence_metadata']['judge_amendment']=TAG
    result.update(s.classify(evaluated))
    return result


def copy_public():
    PUBLIC.mkdir(parents=True,exist_ok=True)
    for p in PRIVATE.rglob('*'):
        if not p.is_file() or p.name=='ledger_before_recovery.json':continue
        if 'original_jobs' in p.relative_to(PRIVATE).parts:continue
        data=p.read_bytes();assert s.sanitize(data.decode('utf-8'))==data.decode('utf-8')
        target=PUBLIC/p.relative_to(PRIVATE);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)


def prepare():
    assert not PRIVATE.exists(),'Preserve a previous recovery; inspect rather than replaying it'
    cfg=s.config();plan=s.verify(cfg);s.old.old.support.no_other_runner(cfg)
    ledger=RAW_LOAD(cfg['budget_ledger_path']);before=Path(cfg['budget_ledger_path']).read_bytes()
    assert (len(ledger['events']),ledger['spent_cny'],ledger['limit_cny'])==(1183,112.728371,210)
    assert 'Isolated F1.4 worker failed' in ledger['halted'] and "invalid literal for int()" in ledger['halted']
    assert s.sha(cfg['budget_ledger_path'])==RAW_LOAD(ROOT/'ledger_checkpoint.json')['sha256']
    events=ledger['events'][s.HISTORY:];assert len(events)==42 and all(e['status']=='settled' for e in events)
    PRIVATE.mkdir(parents=True)
    (PRIVATE/'ledger_before_recovery.json').write_bytes(before)
    original_files={}
    for p in (ROOT/'jobs').rglob('*'):
        if not p.is_file():continue
        rel=p.relative_to(ROOT/'jobs');original_files[rel.as_posix()]=s.sha(p)
        target=PRIVATE/'original_jobs'/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(p.read_bytes())
    for name in ('study_state.json','active_run.json','ledger_checkpoint.json','status.json','实验状态.md','status.html'):
        shutil.copyfile(ROOT/name,PRIVATE/('before_'+name))
    log=subprocess.run([sys.executable,'-B','-X','utf8','-m','unittest','discover','-s','progress/tests','-p','test_recover_f14_v5_string.py','-v'],
        cwd=s.REPO,capture_output=True,text=True,encoding='utf-8',timeout=120)
    (PRIVATE/'free_tests.log').write_text(log.stdout+log.stderr,encoding='utf-8');assert log.returncode==0,log.stderr
    calibration=subprocess.run([sys.executable,'-B','-X','utf8',str(EXT/'local_probe.py'),'calibrate'],
        cwd=s.REPO,capture_output=True,text=True,encoding='utf-8',timeout=60)
    assert calibration.returncode==0,calibration.stderr
    checks=json.loads(calibration.stdout)
    assert checks['reference_cases']==946 and checks['negative_controls']==35 and not checks['private_rename_regressions']
    s.atomic_json(PRIVATE/'judge_calibration.json',checks)
    probe=RAW_LOAD(NATIVE_PROBE/'result.json');assert probe['status']=='passed' and probe['native_execution'] and not probe['cleanup_errors']
    for name in ('job.json','result.json','completion.json','FB.st','PLC_PRG.st','stdout.log','stderr.log'):
        target=PRIVATE/'native_probe'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(NATIVE_PROBE/name,target)
    for name in ('result.json','FB.st','PLC_PRG.st'):
        target=PRIVATE/'native_probe_initial_one_based'/name;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(NATIVE_PROBE.with_name('f14_v5_string_probe_20261112')/name,target)
    proofs=[p for p in EXT.glob('*.py')]+[Path(__file__),s.REPO/'progress/tests/test_recover_f14_v5_string.py']
    s.atomic_json(PRIVATE/'recovery_plan.json',dict(tag=TAG,user_authorization='重新启动测试',
        original_plan_sha256=s.sha(ROOT/'study_plan.json'),ledger_sha256=s.sha(cfg['budget_ledger_path']),
        initial_events=1183,initial_spent_cny=112.728371,requests_already_settled=42,maximum_new_requests=0,
        original_job_files=original_files,source_files={p.relative_to(s.REPO).as_posix():s.sha(p) for p in proofs},
        native_probe_result_sha256=s.sha(PRIVATE/'native_probe/result.json'),preserve_course_character_view=True,
        native_byte_context='ASCII STRING scalar index is zero-based; terminator byte is zero; beyond terminator/code-page cases remain unresolved'))
    assert Path(cfg['budget_ledger_path']).read_bytes()==before
    copy_public()
    print('PREPARED free recovery: 42 settled responses, 24 jobs, zero additional model calls',flush=True)


def run():
    cfg=s.config();s.verify(cfg);proof=RAW_LOAD(PRIVATE/'recovery_plan.json')
    for path,digest in proof['source_files'].items():assert s.sha(s.REPO/path)==digest
    assert s.sha(cfg['budget_ledger_path'])==proof['ledger_sha256']
    ledger=RAW_LOAD(cfg['budget_ledger_path']);plan=RAW_LOAD(ROOT/'study_plan.json')
    events={(e['request']['job_id'],e['request']['candidate_index']):e for e in ledger['events'][s.HISTORY:]}
    s.atomic_json(ROOT/'study_state.json',dict(state='running',at=s.stamp(),completed=23,mode='free_judge_recovery',new_model_calls=0))
    tasks=[];records={};started=time.monotonic()
    for job in plan['jobs']:
        record=copy.deepcopy(RAW_LOAD(ROOT/'jobs'/job['condition']/(job['pid']+'.json')));records[job['job_id']]=record
        for idx in (0,1):
            event=events.get((job['job_id'],idx))
            if not event:continue
            original=record['attempts'][idx] if idx<len(record['attempts']) else reconstruct(job,event)
            tasks.append((job,original))
    assert len(tasks)==42
    results={}
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures={pool.submit(evaluate_attempt,job,a):(job['job_id'],a['idx']) for job,a in tasks}
        for future in as_completed(futures):
            key=futures[future];results[key]=future.result()
            print('FREE JUDGE',len(results),'/42',flush=True)
    effective={}
    for job in plan['jobs']:
        record=records[job['job_id']]
        record['attempts']=[results[(job['job_id'],idx)] for idx in (0,1) if (job['job_id'],idx) in results]
        record.update(job_done=True,best_attempt=s.select_best(record['attempts']),judge_amendment=TAG,
            recovered_from_original_record_sha256=proof['original_job_files'][job['condition']+'/'+job['pid']+'.json'])
        if not records[job['job_id']]['stop_reason']:
            record['stop_reason']='existing_settled_response_evaluated_after_judge_repair'
        path=PRIVATE/'effective_jobs'/job['condition']/(job['pid']+'.json');s.atomic_json(path,record)
        effective[ROOT/'jobs'/job['condition']/(job['pid']+'.json')]=path
    for rel,digest in proof['original_job_files'].items():assert s.sha(ROOT/'jobs'/rel)==digest
    assert s.sha(cfg['budget_ledger_path'])==proof['ledger_sha256']
    # Publish a separate result view; raw answer/request/response files remain byte-for-byte untouched.
    def load(path):return RAW_LOAD(effective.get(Path(path),Path(path)))
    s.load=load
    audit=reporting.audit_final(cfg,plan)
    audit.update(judge_amendment=TAG,new_model_calls=0,original_job_files_unchanged=True,free_replay_seconds=round(time.monotonic()-started,3))
    s.atomic_json(PRIVATE/'final_audit_before_recovery_marker.json',audit)
    with ledger_lock(cfg['budget_ledger_path']):
        path=Path(cfg['budget_ledger_path']);assert s.sha(path)==proof['ledger_sha256']
        current=RAW_LOAD(path)
        current.setdefault('recoveries',[]).append(dict(reason='close_verified_v5_string_byte_judge_failure',at=s.stamp(),
            recovery_plan_sha256=s.sha(PRIVATE/'recovery_plan.json'),previous_halt=current['halted'],
            events_unchanged=1183,spent_cny_unchanged=112.728371,new_model_calls=0))
        current['halted']='';current.pop('halt_details',None)
        assert current['events']==ledger['events'] and current['spent_cny']==ledger['spent_cny']
        s.atomic_json(path,current)
    audit['ledger_sha256']=s.sha(cfg['budget_ledger_path'])
    s.atomic_json(ROOT/'final_audit.json',audit)
    s.atomic_json(ROOT/'completion.json',dict(completed=True,jobs=24,requests=42,accounted_cny=112.728371,at=s.stamp(),judge_amendment=TAG,new_model_calls=0))
    s.atomic_json(ROOT/'study_state.json',dict(state='completed',at=s.stamp(),completed=24,judge_amendment=TAG,new_model_calls=0))
    marker=RAW_LOAD(ROOT/'active_run.json');marker.update(state='completed',recovered_at=s.stamp(),judge_amendment=TAG);s.atomic_json(ROOT/'active_run.json',marker)
    s.atomic_json(ROOT/'ledger_checkpoint.json',dict(sha256=s.sha(cfg['budget_ledger_path']),at=s.stamp()))
    copy_public();summary=reporting.report(cfg,plan)
    summary.update(judge_amendment=TAG,effective_records='operational_restarts/'+TAG+'/effective_jobs',new_model_calls=0)
    note='\n判题接续：原模型请求已全部完成并结算，免费复验42份现有答卷后覆盖24/24题次，没有追加模型请求。字符串BYTE转换按真实CODESYS仿真核验的0基字节索引处理；课程原字符视图保留，超出已建模范围单列未决。原始答卷、提示、响应、费用、冻结裁判均保留，派生记录见operational_restarts/'+TAG+'/effective_jobs。\n'
    for folder in (ROOT,s.MIRROR):
        s.atomic_json(folder/'status.json',summary)
        for name in ('实验状态.md','最终报告.md'):
            p=folder/name
            if p.exists():p.write_text(p.read_text(encoding='utf-8')+note,encoding='utf-8')
        p=folder/'status.html';p.write_text(p.read_text(encoding='utf-8').replace('</pre>',note+'</pre>'),encoding='utf-8')
    with zipfile.ZipFile(s.MIRROR/'验收包.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for p in s.MIRROR.rglob('*'):
            if p.is_file() and p.suffix!='.zip':archive.write(p,p.relative_to(s.MIRROR).as_posix())
    print('COMPLETED 24/24; 42 settled requests; no new model fee; accounted 112.728371',flush=True)


if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='prepare':prepare()
    elif len(sys.argv)>1 and sys.argv[1]=='run':run()
    else:raise SystemExit('Use prepare, then run. This entry never generates candidates.')
