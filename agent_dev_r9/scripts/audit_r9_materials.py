"""Audit original properties, observable bindings and pending process reviews without model calls."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.cli import problems,reference
from stbench.portability import adapt
from stbench.spec_policy import formula_names
from stbench.spec_observers import observer_for
from stbench.evaluation import atomic_json,local_tests


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--reviewer',default='');args=ap.parse_args()
    args.out.mkdir(parents=True,exist_ok=False)
    origin=json.loads((ROOT/'ORIGIN_R8.json').read_text(encoding='utf-8'))
    for name,expected in origin['files'].items():
        if hashlib.sha256((Path(origin['source_root'])/name).read_bytes()).hexdigest()!=expected:
            raise RuntimeError('R8 source or dataset changed: '+name)
        if name.startswith('datasets/') and hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=expected:
            raise RuntimeError('Original R9 dataset was edited: '+name)
    missing=[];bindings=[];refs=[];reviews=[]
    new_ids={'self-hard-05','self-hard-06','self-hard-07','self-medium-05','self-medium-06'}
    for original in problems():
        p,code,_=adapt(original,reference(original),'codesys')
        judged=local_tests(code,p)
        refs.append(dict(pid=p.pid,passed=judged.tests_passed,total=judged.tests_total,compiles=judged.compiles,error=judged.failure_summary))
        replacements={s.sid:s for s in p.specs}
        for spec in original.specs:
            if not spec.ltl:
                updated=replacements[spec.sid]
                missing.append(dict(pid=p.pid,sid=spec.sid,text=spec.text,r9_formula=updated.ltl,
                    status='formalized' if updated.ltl else 'simulation_only_pending',
                    next_step='reference and mutation checks' if updated.ltl else 'Define an input-history observer or retain the explicit simulation boundary'))
        observer=observer_for(p.provenance['r9_spec_policy']['observer'])
        allowed={v.name.lower() for v in p.variables}|(set(observer({},None,True)) if observer else set())
        for spec in p.specs:
            if spec.ltl:
                private=sorted(formula_names(spec.ltl)-allowed)
                if private:bindings.append(dict(pid=p.pid,sid=spec.sid,unbound_private_names=private,
                                               result='inconclusive, never counted as passed'))
        if p.pid in new_ids:
            reviews.append(dict(pid=p.pid,title=p.title,source=original.provenance,
                automatic_reference_cases=f'{judged.tests_passed}/{judged.tests_total}',
                human_process_review='pending',assigned_reviewer=args.reviewer or None,
                reviewer=None,review_date=None,signoff=None,
                required_review=['工艺边界与安全侧行为','输入单位、量程与采样周期','复位/故障/正常动作优先级',
                                 '公式和阈值的适用条件','原有用例及未覆盖工况']))
    if any(not r['compiles'] or r['passed']!=r['total'] for r in refs):
        raise RuntimeError('Adapted reference tests failed; inspect audit records')
    result=dict(r8_files_unchanged=True,original_cases_unchanged=True,reference_passed=sum(r['passed'] for r in refs),
        reference_total=sum(r['total'] for r in refs),original_simulation_only=len(missing),
        newly_formalized=sum(bool(r['r9_formula']) for r in missing),remaining_simulation_only=sum(not r['r9_formula'] for r in missing),
        unbound_specs=len(bindings),human_reviews_pending=len(reviews),generation_requests=0)
    atomic_json(args.out/'summary.json',result);atomic_json(args.out/'property_audit.json',missing)
    atomic_json(args.out/'binding_audit.json',bindings);atomic_json(args.out/'reference_tests.json',refs)
    atomic_json(args.out/'human_review.json',reviews)
    lines=['# R9 规约与工艺审核清单','','自动工程复核不替代人工工艺确认。上游 provenance 中的人工审核措辞只是来源声明，未视为已经签署的审核证据。','',
           f"原有 28 条仅测试覆盖性质中，{result['newly_formalized']} 条增加了公式，{result['remaining_simulation_only']} 条继续明确列为测试覆盖。适配参考用例 {result['reference_passed']}/{result['reference_total']}。",'',
           '|题号|性质|处理|','|---|---|---|']
    for row in missing:lines.append(f"|{row['pid']}|{row['sid']}|{'新增公式，待有界检查' if row['r9_formula'] else '保留测试覆盖，待观察器建模'}|")
    lines+=['','## 五道新增工业题的人工复核','','|题号|主题|自动用例|审核人|结论|','|---|---|---|---|---|']
    for row in reviews:lines.append(f"|{row['pid']}|{row['title']}|{row['automatic_reference_cases']}|{row['assigned_reviewer'] or '待填写'}|待工艺复核|")
    lines+=['','逐题核对单位、阈值、失效安全侧、复位和故障优先级及未覆盖工况；审核人确认后再记录日期和结论。',
            '',f"另有 {len(bindings)} 条公式仍引用未绑定的候选内部名称，运行时单列为无法判定，不能算作通过；详见 binding_audit.json。",'']
    (args.out/'审核清单.md').write_text('\n'.join(lines),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))
    return 0


if __name__=='__main__':raise SystemExit(main())
