"""Offline audit of the stopped first request. Never calls an external service."""
import http.client
import io
import json
from pathlib import Path
import sys
from unittest.mock import patch
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parent))
import full_r8_study as s
from stbench import transport,transport_worker

def simulate(body=None,error=None):
    class Response:
        headers={'Content-Type':'text/event-stream'}
        def __enter__(self):return self
        def __exit__(self,*args):return False
        def read(self):
            if error:raise error
            return body
    job=dict(url='https://offline.invalid/responses',payload={},key='offline-fixture',timeout=1)
    output=io.StringIO()
    with patch.object(transport.urllib.request,'urlopen',return_value=Response()) as fake:
        with patch.object(sys,'stdin',io.StringIO(json.dumps(job))),patch.object(sys,'stdout',output):
            transport_worker.main()
        assert fake.call_count==1
    return json.loads(output.getvalue())

def inspect():
    cfg=s.config();root=Path(cfg['campaign_root']);plan=s.load(root/'study_plan.json');s.verify(root)
    assert s.load(root/'study_state.json')['state']=='stopped'
    assert not s.old.support.registered_process_alive(s.load(root/'active_run.json'))
    ledger=s.history(cfg,root,plan);new=ledger['events'][450:]
    assert len(new)==1 and new[0]['status']=='reserved' and ledger['halted']
    assert new[0]['request']['job_id']=='custom_deepseek-v4pro/public-easy-01'
    assert len(list((root/'jobs').rglob('*.request_*.json')))==1
    assert not list((root/'jobs').rglob('*.response_*.json'))
    record=s.load(root/'jobs/custom_deepseek-v4pro/public-easy-01.json')
    assert len(record['attempts'])==1 and not record['attempts'][0]['code']
    assert s.money(ledger['spent_cny'])==s.money(s.BASELINE)+s.money(new[0]['reserved_cny'])
    cases=dict(incomplete_http_body=simulate(error=http.client.IncompleteRead(b'data:',100)),
               non_object_sse_event=simulate(body=b'data: null\n\n'),
               completed_sse_control=simulate(body=b'data: {"type":"response.completed","response":{"model":"fixture","status":"completed"}}\n\n'),
               malformed_json_control=simulate(body=b'data: {broken\n\n'))
    generic='Upstream worker malformed result; no automatic retry'
    assert cases['incomplete_http_body']['error']==generic==cases['non_object_sse_event']['error']
    assert cases['completed_sse_control']['ok'] is True
    assert cases['malformed_json_control']['error']!=generic
    return dict(audit_passed=True,external_requests=0,first_request_id=new[0]['request_id'],
                sent_requests=1,complete_jobs=0,remaining_unstarted_jobs=139,partial_jobs=1,
                confirmed_new_cost_cny=0,unknown_new_reserved_cny=new[0]['reserved_cny'],
                total_accounted_cny=ledger['spent_cny'],ledger_sha256=s.sha(cfg['budget_ledger_path']),
                history_preserved=True,old_event_count=450,halted=ledger['halted'],observed_error=generic,
                finding='The existing classification conflates distinct causes; original root cause and charge remain unknown.',
                offline_cases=cases,source_sha256=s.sha(Path(__file__)))

def make():
    cfg=s.config();root=Path(cfg['campaign_root']);result=inspect()
    assert not (root/'stop_manifest.json').exists(),'Stop archive is frozen'
    text='''# 全量实验首次请求中止记录

免费准备已完成：141项回归通过，140条本地假响应通道通过，其中70条真实Codex CLI；冻结准备提交272b182。模型调用前已推送；170元新授权及80元人工检查点均已生效，历史450条事件、恢复记录和未知预留保留。

## 实际运行状态

仅发送1次请求：自研DeepSeek，public-easy-01，Responses协议。约103.094秒后返回“Upstream worker malformed result; no automatic retry”。没有返回可核对的模型身份、用量、代码或完整响应；未执行原生编译、功能或形式检查。首题未完成，其余139题次未启动；0/140完整归档，不能据此计算模型正确率。

新增已确认费用为0元，新增未知预留0.430347元暂时保留；共享账本累计计入40.145743元。未知预留不表示确认扣费，也不能视为免费请求。没有清除账本停止状态、没有退款冲销、没有重试、降输出额度或切换API。停止原因是未知上游结果，不是达到80元检查点。

## 免费诊断结论

冻结的HTTP工作进程只记录通用异常分类，没有保留具体异常类型或原始异常响应。本地模拟表明，HTTP响应体未读完整及SSE事件为非对象，均可产生同一错误分类；因此无法据现有日志确定这次真实故障属于哪一种，也不能确定是网络、提供方还是兼容性问题。模拟未访问外网、未产生任何模型费用。

独立诊断工具及stop_audit.json保留这些可复现证据，没有修改已冻结的传输实现。后续需要先核对提供方在2026-11-10 17:01:18至17:03:01（北京时间）、deepseek-v4-pro-0813请求的调用记录和费用。账本request_id是本地编号，不冒充供应商请求编号。

## 接续边界

本批次保留为停止现场，不伪造完成或推断未运行题目成绩。不得直接重跑该首请求、解除未知费用或把新提供方结果混入本批次。费用确认后，另立版本改进异常类型和响应留痕，并经免费模拟验收、重新冻结和预算核算，再按用户指示决定后续实验。

总授权170元、接近80元暂停约定继续保留，不因本次故障自动扩大预算。
'''
    logs={}
    for name in ('live.stdout.log','live.stderr.log'):
        logs[name]=s.old.support.sanitize((root/name).read_text(encoding='utf-8'))
    for destination in (root,s.MIRROR):
        s.atomic_json(destination/'stop_audit.json',result)
        (destination/'运行中止报告.md').write_bytes(text.encode())
        target=destination/'stop_diagnostics';target.mkdir(exist_ok=True)
        for name,content in logs.items():(target/name).write_bytes(content.encode())
    files={p.relative_to(s.MIRROR).as_posix():s.sha(p) for p in s.MIRROR.rglob('*') if p.is_file()}
    manifest=dict(kind='stopped_full_r8_first_request',files=files,source_sha256=result['source_sha256'],
                  archive_type='failure evidence, not completed experiment acceptance')
    for destination in (root,s.MIRROR):s.atomic_json(destination/'stop_manifest.json',manifest)
    archive=root/'停止现场包.zip'
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for p in s.MIRROR.rglob('*'):
            if p.is_file():z.writestr('evidence/'+p.relative_to(s.MIRROR).as_posix(),p.read_bytes())
        for p in s.source_files()+[Path(__file__)]:z.writestr('source/'+p.relative_to(s.REPO).as_posix(),p.read_bytes())
    with zipfile.ZipFile(archive) as z:assert z.testzip() is None
    (s.MIRROR/archive.name).write_bytes(archive.read_bytes())
    for destination in (root,s.MIRROR):
        s.atomic_json(destination/'stop_package_manifest.json',dict(archive=archive.name,sha256=s.sha(archive)))
    print('PASS stopped-run archive; no new external requests; unknown reserve retained')

def check():
    cfg=s.config();root=Path(cfg['campaign_root']);result=inspect()
    assert result==s.load(root/'stop_audit.json')==s.load(s.MIRROR/'stop_audit.json')
    manifest=s.load(root/'stop_manifest.json');assert manifest==s.load(s.MIRROR/'stop_manifest.json')
    for name,digest in manifest['files'].items():assert s.sha(root/name)==digest==s.sha(s.MIRROR/name),name
    package=s.load(root/'stop_package_manifest.json')
    assert s.sha(root/package['archive'])==package['sha256']==s.sha(s.MIRROR/package['archive'])
    print('PASS frozen stopped-run evidence, original history and unchanged ledger')

if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='check':check()
    else:make()
