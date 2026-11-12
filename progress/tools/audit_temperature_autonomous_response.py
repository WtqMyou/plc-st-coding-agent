"""Verify raw provider provenance and combined accounting for the successful targeted repair."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import f14_v9_temperature_core as s


def main():
    cfg=s.config();root=Path(cfg['campaign_root']);audit=s.load(root/'final_audit.json')
    ledger=Path(cfg['budget_ledger_path']);checkpoint=root/'ledger_after_study.json'
    if not checkpoint.exists():
        assert s.sha(ledger)==audit['ledger_sha256'];shutil.copyfile(ledger,checkpoint)
    assert s.sha(checkpoint)==audit['ledger_sha256']
    frozen=s.load(checkpoint);current=s.load(ledger)
    assert s.parent.prefix_ok(current,frozen)
    plan=s.load(root/'study_plan.json');job=plan['jobs'][0]
    folder=root/'jobs'/job['condition'];record=s.load(folder/(s.PID+'.json'))
    initial=s.load(s.PACK/'initial_messages.json')['messages'];seed=s.load(s.PACK/'seed_metadata.json')
    assert hashlib.sha256(initial[1]['content'].encode()).hexdigest()==seed['original_user_sha256']
    assert hashlib.sha256(initial[2]['content'].encode()).hexdigest()==seed['original_candidate_sha256']
    assert not seed['developer_patch_used'] and not seed['reference_answer_used']
    assert s.sha(s.REPO/seed['original_job_path'])==seed['original_job_sha256']
    assert all('"expected":' not in message['content'] and '"note":' not in message['content'] for message in initial)
    spec=importlib.util.spec_from_file_location('audited_public_time_tool',s.PACK/'public_time_bounds.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    analysis=s.load(s.PACK/'public_time_analysis.json')
    assert not analysis['test_cases_read'] and analysis['rules']==module.derive(initial[1]['content'],1)
    rows=[]
    for a in record['attempts']:
        idx=a['idx'];response=s.load(folder/(s.PID+f'.response_{idx+1:02}.json'))
        request=s.load(folder/(s.PID+f'.request_{idx+1:02}.json'))
        assert request['messages'][:len(initial)]==initial
        assert request['parameters']==cfg['models'][0]['parameters'] and request['max_output_tokens']==16384
        raw=response['raw_response'];assert response['protocol']=='responses'
        assert raw['model']==a['actual_model']
        text='\n'.join(c.get('text','') for output in raw.get('output',[]) if output.get('type')=='message'
                       for c in output.get('content',[]) if c.get('type')=='output_text')
        extracted=s.extract_code(text)
        original=(folder/(s.PID+f'.raw_candidate_{idx+1:02}.st')).read_bytes()
        assert original==extracted.encode()
        normalized,edits=s.normalize(extracted);assert normalized==a['code'] and edits==a['format_edits']
        assert hashlib.sha256(normalized.encode()).hexdigest()==a['code_hash']
        event=next(e for e in frozen['events'][s.HISTORY:] if e['request']['candidate_index']==idx)
        assert event['status']=='settled' and event['metadata']['model']==a['actual_model']
        assert s.money(event['accounted_cny'])==s.money(a['cost_cny'])
        for field in ('prompt_tokens','completion_tokens'):assert event['metadata'][field]==a[field]
        native=a['judge']['platform_results']['codesys']
        assert native['source_sha256']==a['code_hash']
        rows.append(dict(candidate=idx+1,model=a['actual_model'],provider_response_id=raw.get('id'),
            raw_model_code_sha256=hashlib.sha256(original).hexdigest(),native_source_sha256=native['source_sha256'],
            original_model_code_used_without_edits=not edits,model_response_matches_evaluated_code=True,
            native_status=native['status'],functional_cases_passed=a['tests_passed'],functional_cases_total=a['tests_total']))
    best=record['attempts'][record['best_attempt']]
    assert record['job_done'] and best['native_pass'] and best['functional_pass'] and best['tests_passed']==37
    assert best['verification_status']!='violated'
    first=s.load(s.REPO/'progress/evidence/f14_v8_temperature_repair_20261113/status.json')
    new_cost=s.money(frozen['spent_cny'])-s.money(122.610403)
    assert new_cost<=s.money(3.261728)
    proof=dict(passed=True,autonomous_repair_goal_achieved=True,developer_source_not_used=True,private_expected_outputs_not_provided=True,
        original_model_seed_verified=True,public_time_arithmetic_recomputed_from_original_task=True,
        raw_response_provenance_verified=True,rows=rows,formal_status=best['verification_status'],
        phase_one_requests=first['requests'],phase_two_requests=len(record['attempts']),total_new_requests=first['requests']+len(record['attempts']),
        first_phase_cost_cny=first['new_accounted_cny'],second_phase_cost_cny=float(s.money(frozen['spent_cny'])-s.money(s.BASELINE)),
        combined_cost_cny=float(new_cost),combined_original_reservation_cny=3.261728,accounted_cny=frozen['spent_cny'],
        all_new_requests_settled=True,ledger_checkpoint_sha256=s.sha(checkpoint),audit_tool_sha256=s.sha(__file__))
    s.atomic_json(root/'autonomous_provenance.json',proof);s.atomic_json(s.MIRROR/'autonomous_provenance.json',proof)
    print('PASS autonomous provenance: raw model response equals tested source; 37/37 and CODESYS passed; combined cost',float(new_cost),flush=True)


if __name__=='__main__':main()
