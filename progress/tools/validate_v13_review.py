"""Offline acceptance and optional real reference compiler checks; no model clients."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO/'progress/v13'))
import revision as v
from stbench.evaluation import local_tests, atomic_json
from stbench.schema import Problem
from stbench.platforms import CodesysBackend, OpenPLCBackend


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--native', choices=['codesys', 'openplc'])
    ap.add_argument('--out', type=Path, required=True)
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    ledger = Path('E:/PLC_Dev/evidence/dmxapi_budget_75.json')
    before = v.digest(ledger.read_bytes())
    cfg = json.loads((v.ENGINE/'config.example.json').read_text('utf-8'))
    assert not cfg['live_enabled'] and not cfg['models']
    if args.native:
        # Fresh positive/negative controls before any reference acceptance.
        cls = CodesysBackend if args.native == 'codesys' else OpenPLCBackend
        backend = cls(cfg)
        p = Problem.from_dict(dict(pid='v13-compiler-control', source='selfmade', difficulty='easy', title='control', requirements='b=a',
            variables=[dict(name='a', data_type='BOOL', direction='input'), dict(name='b', data_type='BOOL', direction='output')]))
        code = 'FUNCTION_BLOCK FB VAR_INPUT a:BOOL; END_VAR VAR_OUTPUT b:BOOL; END_VAR b:=a; END_FUNCTION_BLOCK'
        controls = dict(positive=backend.compile(code, p).to_dict(), negative=backend.compile(code.replace('b:=a;', 'b:=;'), p).to_dict())
        controls['passed'] = controls['positive']['status'] == 'passed' and controls['negative']['status'] == 'failed'
        atomic_json(args.out/(args.native+'_controls.json'), controls)
        if not controls['passed']: raise RuntimeError('Native compiler controls failed')
        if args.native == 'codesys':
            # Reuse the frozen, nonce-checked batch implementation, explicitly
            # binding new tasks and redirecting its only source-tree output.
            batch = load('v13_codesys_batch', v.ENGINE/'scripts/codesys_reference_batch.py')
            batch.problems, batch.reference, batch.adapt = v.problems, v.reference, v.adapt
            batch.config = lambda _: cfg
            batch.export_summary = lambda _old_path, rows: atomic_json(args.out/'codesys_references.json', rows)
            sys.argv = [str(v.ENGINE/'scripts/codesys_reference_batch.py'), '--adapted']
            if batch.main(): raise RuntimeError('CODESYS reference compilation failed')
        else:
            rows = []
            for p in v.problems():
                q, code, mapping = v.adapt(p, platform='openplc')
                row = dict(pid=p.pid, adaptation=mapping, **backend.compile(code, q).to_dict())
                rows.append(row)
                atomic_json(args.out/'openplc_references.json', rows)
                print(p.pid, row['status'], flush=True)
            if any(r['status'] != 'passed' for r in rows): raise RuntimeError('OpenPLC reference compilation failed')
    else:
        from stbench.spec_policy import formula_names
        audit = load('v13_formula_audit', REPO/'progress/tools/audit_review_20261108.py')
        rows = []
        for p in v.problems():
            q, code, mapping = v.adapt(p)
            r = local_tests(code, q)
            row = dict(pid=p.pid, tests_passed=r.tests_passed, tests_total=r.tests_total, compiles=r.compiles,
                errors=r.compile_errors, failures=[c.to_dict() for c in r.cases if not c.passed])
            if p.pid in v.FIVE:
                row['formula_replay'] = audit.replay(q, code)
            rows.append(row)
        runtime = [s for p in v.problems() for s in v.adapt(p)[0].specs]
        original = [s for p in v.problems() for s in p.specs]
        for p in v.problems():
            q, _, _ = v.adapt(p)
            allowed = {x.name.lower() for x in q.variables}
            for s in q.specs:
                if s.ltl and p.pid in v.FIVE:
                    assert formula_names(s.ltl) <= allowed, (p.pid, s.sid, formula_names(s.ltl)-allowed)
        good = all(r['compiles'] and r['tests_passed'] == r['tests_total'] for r in rows)
        good = good and all(s.get('holds') and not s.get('error') for r in rows for s in r.get('formula_replay', {}).get('formulas', []))
        result = dict(version=v.VERSION, passed=good, model_calls=0, cases=sum(r['tests_total'] for r in rows),
            cases_passed=sum(r['tests_passed'] for r in rows), raw_ltl=sum(bool(s.ltl) for s in original),
            runtime_ltl=sum(bool(s.ltl) for s in runtime), total_properties=len(runtime), rows=rows,
            mc_scope='given test sequences only; no exhaustive search claimed')
        atomic_json(args.out/'offline.json', result)
        if not good: raise RuntimeError('Offline validation failed')
    assert v.digest(ledger.read_bytes()) == before, 'Ledger changed during offline work'
    print('PASS', args.native or 'offline', 'ledger unchanged', flush=True)


if __name__ == '__main__': main()
