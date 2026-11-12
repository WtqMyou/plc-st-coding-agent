"""Full-study read-only status server and candidate-level final evidence audit."""
from collections import Counter
from html import escape
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import zipfile
LABELS={'custom_deepseek-v4pro':'自研 DeepSeek','codex_deepseek-v4pro':'Codex DeepSeek',
        'custom_minimax-m27':'自研 MiniMax','codex_minimax-m27':'Codex MiniMax'}
STATES={'prepared':'准备完成','running':'运行中','completed':'140题次完成','stopped':'已停止，保留现场'}

from f14_v10_dashboard import report


def serve(cfg,port):
    root=Path(cfg['campaign_root'])
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            name=self.path.split('?',1)[0].lstrip('/') or 'status.html'
            if name not in ('status.html','status.json') or not (root/name).is_file():self.send_error(404);return
            data=(root/name).read_bytes();self.send_response(200)
            self.send_header('Content-Type','text/html; charset=utf-8' if name.endswith('.html') else 'application/json; charset=utf-8')
            self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
        def log_message(self,*args):pass
    ThreadingHTTPServer(('127.0.0.1',port),Handler).serve_forever()

def audit_final(cfg,plan):
    import f14_v10_core as s
    root=Path(cfg['campaign_root']);state=s.load(cfg['budget_ledger_path'])
    events=state['events'][s.HISTORY:]
    linked={(e['request']['job_id'],e['request']['candidate_index']):e for e in events}
    assert len(linked)==len(events)<=560 and s.prefix_ok(state,s.load(root/'ledger_before_study.json'))
    assert len(plan['jobs'])==140 and plan['planned']==140 and plan['maximum_requests']==560
    conditions=Counter(j['condition'] for j in plan['jobs']);assert len(conditions)==4 and set(conditions.values())=={35}
    assert sum(len(p['test_cases']) for p in s.tasks().values())==946
    requests=0
    for job in plan['jobs']:
        folder=root/'jobs'/job['condition'];record=s.load(folder/(job['pid']+'.json'))
        assert record['job_done'] and record['best_attempt']==s.select_best(record['attempts'])
        assert len(record['attempts']) in (1,2,3,4)
        for index,a in enumerate(record['attempts']):
            event=linked[(job['job_id'],index)];assert event['status']=='settled'
            assert s.money(event['accounted_cny'])==s.money(a['cost_cny'])
            assert a['actual_model']==event['metadata']['model']
            for field in ('prompt_tokens','completion_tokens'):assert a[field]==event['metadata'][field]
            assert (folder/(job['pid']+f'.request_{index+1:02}.json')).is_file()
            assert (folder/(job['pid']+f'.response_{index+1:02}.json')).is_file()
            if a['code']:
                raw=(folder/(job['pid']+f'.raw_candidate_{index+1:02}.st')).read_bytes().decode()
                normalized,edits=s.normalize(raw)
                assert normalized==a['code'] and edits==a['format_edits']
                assert (folder/(job['pid']+f'.candidate_{index+1:02}.st')).read_bytes()==normalized.encode()
                assert s.hashlib.sha256(normalized.encode()).hexdigest()==a['code_hash']
                native=a.get('judge',{}).get('platform_results',{}).get('codesys',{})
                if native.get('status')=='passed':assert native['source_sha256']==a['code_hash']
            requests+=1
    assert requests==len(events)
    return dict(passed=True,jobs=140,requests=requests,cases_per_arm=sum(len(p['test_cases']) for p in s.tasks().values()),normalization_reproducible=True,
        original_events_preserved=True,all_new_requests_settled=True,accounted_cny=state['spent_cny'],ledger_sha256=s.sha(cfg['budget_ledger_path']))
