"""Post-hoc extraction and native conversion audit; never alters candidates or scores."""
import hashlib
from pathlib import Path
import re
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import r4_check_order as study
from stbench.providers.base import extract_code
from stbench.schema import Problem


def main():
    cfg=study.configuration(str(study.CONFIG));root=Path(cfg['campaign_root']);study.verify_frozen(root)
    if study.load(root/'study_state.json').get('state')!='completed':
        raise RuntimeError('Finish the pilot before additional native compilation')
    target=root/'posthoc_native_boundary.json'
    assert not target.exists(),'Existing audit is immutable; use another version'
    plan=study.load(root/'study_plan.json');tasks=study.selected();queue=[];extraction=[]
    for job in plan['jobs']:
        folder=root/'jobs'/job['condition'];record=study.load(folder/(job['pid']+'.json'))
        for attempt in record['attempts']:
            response=folder/f"{job['pid']}.response_{attempt['idx']+1:02}.json"
            body=(study.load(response).get('message') or {}).get('content') or ''
            selected=extract_code(body)
            if attempt.get('provider_error'):extraction_status='generation_error_no_candidate'
            else:extraction_status='matches_record' if selected.replace('\r\n','\n')==attempt['code'].replace('\r\n','\n') else 'mismatch_requires_review'
            extraction.append(dict(job_id=job['job_id'],attempt=attempt['idx'],status=extraction_status,
                fenced_blocks=len(re.findall(r'```[^\n]*\n.*?```',body,re.S)),
                raw_end_fb_present=bool(re.search(r'\bEND_FUNCTION_BLOCK\b',body,re.I)),
                selected_end_fb_present=bool(re.search(r'\bEND_FUNCTION_BLOCK\b',attempt['code'],re.I)),
                raw_body_sha256=hashlib.sha256(body.encode()).hexdigest(),candidate_sha256=hashlib.sha256(attempt['code'].encode()).hexdigest()))
            errors=(attempt.get('judge') or {}).get('compile_errors',[])
            if errors and all(e.get('code')=='E_UNKNOWN_FUNC' for e in errors) and any('TO_INT' in e.get('message','') for e in errors):
                assert hashlib.sha256(attempt['code'].encode()).hexdigest()==attempt['code_hash']
                queue.append(dict(job=job,attempt=attempt['idx'],source=attempt['code'],candidate_sha256=attempt['code_hash']))
    study.atomic_json(root/'extraction_audit.json',dict(model_calls=0,scope='raw returned body only; reasoning never used as code',rows=extraction))
    assert all(r['status']!='mismatch_requires_review' for r in extraction)
    rows=[]
    controls=study.load(root/'native_preflight.json')
    for cls in (study.support.CodesysBackend,study.support.OpenPLCBackend):
        backend=cls(cfg)
        assert backend.identity()==controls[backend.name]['positive']['platform_identity']
        p=Problem.from_dict(dict(pid='r4-generic-conversion-control',source='selfmade',difficulty='easy',title='generic DINT conversion',requirements='y=TO_INT(x)',
            variables=[dict(name='x',data_type='DINT',direction='input'),dict(name='y',data_type='INT',direction='output')]))
        code='FUNCTION_BLOCK FB VAR_INPUT x:DINT; END_VAR VAR_OUTPUT y:INT; END_VAR y:=TO_INT(x); END_FUNCTION_BLOCK'
        report=backend.compile(code,p).to_dict()
        rows.append(dict(kind='minimal_TO_INT_DINT_control',platform=backend.name,source_sha256=hashlib.sha256(code.encode()).hexdigest(),result=report))
        study.atomic_json(target,dict(complete=False,model_calls=0,rows=rows))
        for entry in queue:
            job=entry['job'];report=backend.compile(entry['source'],tasks[job['pid']]).to_dict()
            rows.append(dict(kind='original_candidate',job_id=job['job_id'],attempt=entry['attempt'],
                platform=backend.name,candidate_sha256=entry['candidate_sha256'],result=report,
                interpretation='native compile acceptance is not proof of functional correctness; frozen r4 scores unchanged'))
            study.atomic_json(target,dict(complete=False,model_calls=0,rows=rows))
            print('native audit',backend.name,job['job_id'],report['status'],flush=True)
    study.atomic_json(target,dict(complete=True,model_calls=0,candidate_count=len(queue),rows=rows,
        source_sha256=study.sha(Path(__file__)),scope='post-hoc language boundary audit only; no modified candidate, no score overwrite'))
    print('PASS extraction audit; native conversion observations saved',flush=True)


if __name__=='__main__':main()
