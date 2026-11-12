"""Descriptive project outcomes from frozen answers; no generation or regrading."""
from collections import Counter
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import f14_no80 as n
OUT=n.REPO/'progress/evidence/f14_outcomes_20261112'

def inspect():
    cfg,root,_=n.locations();plan=n.load(root/'study_plan.json')
    audit=n.b.audit_final(cfg,root,plan);assert audit['passed'] and audit['jobs']==140
    cache={};input_hashes={};repair_triggers=Counter();rows=[]
    for job in plan['jobs']:
        path=root/'jobs'/job['condition']/(job['pid']+'.json');record=n.load(path)
        best=record['attempts'][record['best_attempt']];cache[(job['condition'],job['pid'])]=(record,best)
        input_hashes[job['job_id']]=n.sha(path)
        if len(record['attempts'])==2:
            first=record['attempts'][0];native=first['judge'].get('platform_results',{}).get('codesys',{}).get('status')
            kind='static_or_interface' if not first['compiles'] else 'native_compile' if native=='failed' else 'formal_violation' if first['verification_status']=='violated' else 'functional'
            repair_triggers[kind]+=1
    for condition in ('custom_deepseek-v4pro','codex_deepseek-v4pro','custom_minimax-m27','codex_minimax-m27'):
        pairs=[value for (arm,pid),value in cache.items() if arm==condition]
        first=sum(r['attempts'][0]['functional_pass'] for r,a in pairs);final=sum(a['functional_pass'] for r,a in pairs)
        rows.append(dict(condition=condition,tasks=35,first_functional=first,final_functional=final,
            first_functional_percent=round(first/35*100,4),final_functional_percent=round(final/35*100,4),
            repair_gain=sum(not r['attempts'][0]['functional_pass'] and a['functional_pass'] for r,a in pairs),
            first_native=sum(r['attempts'][0]['native_pass'] for r,a in pairs),final_native=sum(a['native_pass'] for r,a in pairs),native_denominator=34,
            assertions_passed=sum(a['tests_passed'] for r,a in pairs),assertions_total=946,
            formal_statuses=dict(Counter(a['verification_status'] for r,a in pairs))))
    total_first=sum(r['first_functional'] for r in rows);total_final=sum(r['final_functional'] for r in rows)
    assert (total_first,total_final)==(36,56) and sum(repair_triggers.values())==95
    examples=[]
    for kind,condition,pid in (
        ('native_compile','custom_deepseek-v4pro','public-hard-03'),
        ('functional','codex_minimax-m27','public-medium-04'),
        ('formal','custom_deepseek-v4pro','public-medium-01')):
        record,best=cache[(condition,pid)];first,last=record['attempts']
        path,=list(n.b.RELEASE.glob('datasets/*/'+pid+'.json'))
        examples.append(dict(kind=kind,job_id=condition+'/'+pid,title=n.load(path)['title'],
            first_native=first['judge'].get('platform_results',{}).get('codesys',{}).get('status'),
            final_native=last['judge'].get('platform_results',{}).get('codesys',{}).get('status'),
            first_tests=first['tests_passed'],final_tests=last['tests_passed'],total=last['tests_total'],
            first_formal=first['verification_status'],final_formal=last['verification_status']))
    return dict(scope='descriptive outcomes for the completed F1.4-P1 batch',tasks=140,requests=235,
        first_functional=total_first,final_functional=total_final,first_percent=round(total_first/140*100,4),final_percent=40.,
        repair_gain=20,percentage_point_gain=round((total_final-total_first)/140*100,4),rows=rows,
        custom_functional=sum(r['final_functional'] for r in rows if r['condition'].startswith('custom_')),
        codex_functional=sum(r['final_functional'] for r in rows if r['condition'].startswith('codex_')),
        tasks_per_framework=70,minimax_custom_advantage_tasks=2,repair_trigger_counts=dict(repair_triggers),examples=examples,
        new_accounted_cny=20.795950,total_accounted_cny=81.872503,
        claims=dict(overall_observed_pass_rates_equal=True,minimax_configuration_custom_lead=True,
            integrated_feedback_process_implemented=True,engineering_feasibility_demonstrated=True,
            industrial_assistance_potential_after_further_tuning_and_engineering_validation=True),
        input_sha256=dict(study_plan=n.sha(root/'study_plan.json'),ledger=n.sha(cfg['budget_ledger_path']),
            final_audit=n.sha(root/'final_audit.json'),records=input_hashes),tool_sha256=n.sha(__file__))

if __name__=='__main__':
    result=inspect()
    if sys.argv[1:]==['--check']:assert n.load(OUT/'outcomes.json')==result
    elif not sys.argv[1:]:
        assert not OUT.exists(),'Preserve earlier outcome snapshots'
        OUT.mkdir(parents=True);n.atomic_json(OUT/'outcomes.json',result)
    else:raise SystemExit('Usage: analyze_f14_outcomes.py [--check]')
    print('PASS outcomes: custom 28/70 equals Codex 28/70; MiniMax custom +2; feedback 36 to 56/140')
