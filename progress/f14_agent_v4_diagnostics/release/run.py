"""Replay all 35 tasks using the supplied ST and the local STBench engine."""
import argparse
import json
from pathlib import Path
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, help='optional JSON report path')
args = parser.parse_args()
sys.path.insert(0, str(Path(__file__).resolve().parent))
from stbench.schema import Problem
from stbench.evaluation import local_tests

here = Path(__file__).resolve().parent
report = {}
failed = False
paths = sorted((here/'datasets').glob('*/*-*.json'))
if len(paths) != 35:
    raise ValueError('Expected 35 tasks')
for path in paths:
    pid = path.stem
    data = json.loads(path.read_text(encoding='utf8'))
    src = (path.parent/'tests'/(pid+'.reference.st')).read_text(encoding='utf8')
    groups = {}
    ids = [case['tc_id'] for case in data['test_cases']]
    if len(ids) != len(set(ids)):
        raise ValueError(pid + ': duplicate test case IDs')
    for case in data['test_cases']:
        mode = case.get('mode') or (data.get('case_mode') or 'single')
        expected = {k.lower() for k in case['expected']}
        outputs = {v['name'].lower() for v in data['variables'] if v.get('direction') in ('output', 'inout')}
        alternatives = case.get('expected_any', [])
        for option in alternatives or [{}]:
            keys = expected | {k.lower() for k in option}
            if (alternatives and not option) or not keys or keys - outputs or (case.get('expect_full') and keys != outputs):
                raise ValueError(f"{pid}/{case['tc_id']}: invalid output assertions")
        if mode not in ('single', 'sequence'):
            raise ValueError(pid + ': unknown case mode ' + str(mode))
        key = (case.get('group', ''), mode)
        groups.setdefault(key, []).append(case)
    results = []
    for (group, mode), cases in groups.items():
        problem = Problem.from_dict({**data, 'case_mode': mode, 'test_cases': cases})
        result = local_tests(src, problem)
        # Detect silently discarded cases at the scoring boundary.
        if result.compiles and (result.tests_total != len(cases) or
                [c.tc_id for c in result.cases] != [c['tc_id'] for c in cases]):
            raise RuntimeError(pid + ': scoring denominator differs from submitted cases')
        results.append(dict(group=group, mode=mode, passed=result.tests_passed,
                            total=result.tests_total, failure=result.failure_summary))
        failed |= result.tests_passed != result.tests_total or bool(result.failure_summary)
    report[pid] = results
    print(pid, ', '.join(f"{r['group'] or r['mode']} {r['passed']}/{r['total']}" for r in results))
print('TOTAL', sum(r['passed'] for rows in report.values() for r in rows), '/', sum(r['total'] for rows in report.values() for r in rows))
if args.output:
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
sys.exit(1 if failed else 0)
