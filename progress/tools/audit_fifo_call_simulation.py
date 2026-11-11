"""Read-only acceptance of the supplied calling program executed in local CODESYS simulation."""
import hashlib
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import validate_fifo_call_simulation as run
s=run.s
OUT=s.REPO/'progress/evidence/fifo_call_simulation_20261111'

def inspect():
    cfg=s.config();root=run.ROOT;base=s.load(root/'baseline.json');live=Path(cfg['campaign_root'])
    s.verify(live)
    assert s.sha(cfg['budget_ledger_path'])==base['ledger_sha256']
    assert s.sha(live/'study_plan.json')==base['original_plan_sha256']
    assert s.sha(live/'验收包.zip')==base['original_package_sha256']
    assert s.sha(cfg['codesys_template'])==base['template_sha256']
    assert s.sha(run.WORKER)==base['worker_sha256'] and s.sha(run.__file__)==base['controller_sha256']
    completion=s.load(root/'completion.json')
    assert completion['verified'] and completion['reference_simulation_passed'] and completion['wrong_count_control_rejected']
    original_fb=(run.SOURCE/'platform_review/portable/public-hard-04.dint-array.st').read_text(encoding='utf-8')
    original_program=(run.SOURCE/'platform_review/portable/PLC_PRG.st').read_text(encoding='utf-8')
    assert hashlib.sha256(original_program.encode()).hexdigest()==base['program_sha256']
    expected={
        'reference':dict(testComplete='TRUE',testPassed='TRUE',firstFailedStep='-1',step='13'),
        'wrong-count-control':dict(testComplete='TRUE',testPassed='FALSE',firstFailedStep='1',step='13')}
    rows=[]
    for name,values in expected.items():
        folder=root/name;job=s.load(folder/'job.json');result=s.load(folder/'result.json')
        assert s.load(folder/'process.json')['returncode']==0
        assert result['nonce']==job['nonce'] and result['status']=='passed' and result['observed_expected']
        assert not result['cleanup_errors'] and result['simulator_logged_out'] and result['project_closed']
        assert result['simulation_only'] and result['simulation_mode_before_login'] and result['simulation_mode_after_stop']
        assert result['combined_build']=='passed' and result['native_execution']
        assert (folder/'PLC_PRG.st').read_bytes()==original_program.encode()
        expected_fb=original_fb if name=='reference' else original_fb.replace('elementCount := count;','elementCount := 0;')
        assert (folder/'FB.st').read_bytes()==expected_fb.encode()
        assert all(result['final_values_normalized'][key]==value for key,value in values.items())
        assert result['task']['calls_after']==[['PLC_PRG','FIFO P1 simulation validation']]
        assert result['task']['kind']=='Cyclic' and result['task']['interval'].lower()=='t#50ms'
        assert result['initial_values_normalized']['step']=='0' and result['initial_values_normalized']['testComplete']=='FALSE'
        rows.append(dict(case=name,combined_build='passed',expected_control_outcome_observed=True,
            raw_final_values=result['final_values'],normalized_final_values=result['final_values_normalized'],
            task=result['task'],runtime_sample_count=len(result['samples']),
            fb_sha256=s.sha(folder/'FB.st'),program_sha256=s.sha(folder/'PLC_PRG.st'),result_sha256=s.sha(folder/'result.json')))
    # Both failures preceded PLC_PRG execution; preserve their sources and diagnostic evidence.
    attempts=[]
    for name in ('fifo_call_simulation_20261111','fifo_call_simulation_20261111_v2'):
        previous=root.with_name(name);baseline=s.load(previous/'baseline.json');result=s.load(previous/'reference/result.json')
        assert not result['native_execution'] and result['combined_build']=='passed'
        assert s.sha(previous/'source/codesys_fifo_call_worker.py')==baseline['worker_sha256']
        assert s.sha(previous/'source/validate_fifo_call_simulation.py')==baseline['controller_sha256']
        attempts.append(dict(directory=name,phase=result['phase'],error=result['error'],native_execution=False))
    ledger=s.load(cfg['budget_ledger_path'])
    return dict(acceptance_passed=True,scope='P1 DINT variant, two supplied non-1-bound instances, local CODESYS simulator',
        supplied_fb_unchanged=True,supplied_plc_program_unchanged=True,capacity_and_bounds=[dict(lower=-2,upper=-1,capacity=2),dict(lower=7,upper=10,capacity=4)],
        test_steps_per_case=14,task_may_cycle_after_completion_but_fb_calls_are_guarded=True,
        reference_test_passed=True,wrong_count_test_passed=False,negative_control_detected=True,
        local_codesys_simulation=True,physical_plc_used=False,course_original_variant_interface_validated=False,
        original_variant_native_build_still_unsupported=True,old_model_results_replaced=False,model_calls=0,
        budget_events=len(ledger['events']),accounted_cny=ledger['spent_cny'],rows=rows,
        setup_attempts_before_execution=attempts,baseline=base,completion=completion,tool_sha256=s.sha(__file__))

if __name__=='__main__':
    result=inspect()
    if sys.argv[1:]==['--check']:
        assert s.load(OUT/'acceptance.json')==result
        for name,digest in s.load(OUT/'delivery_manifest.json').get('files',{}).items():assert s.sha(OUT/name)==digest
        print('PASS two-instance CODESYS simulation, wrong-count detection, original sources and fee history')
    elif not sys.argv[1:]:
        OUT.mkdir(parents=True,exist_ok=True);s.atomic_json(OUT/'acceptance.json',result)
        print('ACCEPTED: local simulator reference passed; wrong-count control failed at test step 1; no model calls')
    else:raise SystemExit('Usage: audit_fifo_call_simulation.py [--check]')
