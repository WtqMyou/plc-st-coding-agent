"""Free diagnostic replay of old answers; never replace official historical scores."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import f14_v2_study as s

def main():
    cfg=s.config();root=Path(cfg['campaign_root']);ledger=Path(cfg['budget_ledger_path']);before=ledger.read_bytes()
    target=s.REPO/'progress/f14_agent_v2/diagnostics';assert not target.exists();target.mkdir()
    previous=s.REPO/'progress/evidence/f14_p1_20261111b/jobs';rows=[]
    for path in sorted(previous.glob('*/*.json')):
        if path.name.count('.')!=1:continue
        record=s.load(path);attempt=record['attempts'][record['best_attempt']] if record.get('best_attempt') is not None else {}
        source=s.extract_code(attempt.get('code',''));old=attempt.get('tests_passed',0)
        static=s.run_stage(source,record['pid'],'static',30) if source else None
        result=s.run_stage(source,record['pid'],'functional',30) if static and static['result']['compiles'] else static
        current=result['result']['tests_passed'] if result else 0
        assert not attempt.get('functional_pass') or current==record['tests_total'],('Lost old functional pass',path,result)
        row=dict(job_id=record['job_id'],old_best_passed=old,new_diagnostic_passed=current,tests_total=record['tests_total'],
            extraction_changed=source!=attempt.get('code',''),old_record_sha256=s.sha(path),new_result=result)
        rows.append(row)
    assert len(rows)==140 and ledger.read_bytes()==before
    improvements=[r for r in rows if r['new_diagnostic_passed']>r['old_best_passed']]
    s.atomic_json(target/'old_answer_replay.json',dict(diagnostic_only=True,new_model_calls=0,records=140,rows=rows,improvements=[r['job_id'] for r in improvements],
        source_batch='f14_p1_20261111b',not_a_new_model_score=True,ledger_unchanged=True))
    origin=s.REPO/'progress/f14_candidate/release';changed=[]
    for p in origin.rglob('*'):
        if p.is_file() and s.sha(p)!=s.sha(s.RELEASE/p.relative_to(origin)):changed.append(p.relative_to(origin).as_posix())
    assert sorted(changed)==['stbench/st/interp.py','stbench/st/typecheck.py']
    s.atomic_json(s.CONFIG.parent/'revision_manifest.json',dict(original_release='progress/f14_candidate/release',changed=changed,
        parent_files={p.relative_to(origin).as_posix():s.sha(p) for p in origin.rglob('*') if p.is_file()},datasets_prompts_references_unchanged=True))
    import f14_v2_native_probe as native
    for name in ('completion.json','result.json','FB.st','PLC_PRG.st'):
        (target/('native_'+name)).write_bytes((native.ROOT/name).read_bytes())
    assert s.sha(s.REPO/'progress/Agent开发测试完整交接包_20261112.zip')=='f5448e23c1d2d684d5da37820a6ac128377f11427d5f08d04be5dc61a1a69158'
    print('PASS 140 historical diagnostic replays; all old functional successes retained; improved:',[r['job_id'] for r in improvements],flush=True)

if __name__=='__main__':main()
