"""Independent calibration of cases, binding, private names and negative controls."""
import json
import re
import sys
from pathlib import Path
from dataclasses import replace
sys.path.insert(0,str(Path(__file__).resolve().parent/'release'))
from stbench.schema import Problem
from stbench.evaluation import local_tests
from stbench.st.typecheck import check_st
from stbench.st.frontend import tokenize
ROOT=Path(__file__).resolve().parent/'release'
def corrupt(value):
    if isinstance(value,bool):return not value,True
    if isinstance(value,(int,float)):return value+13,True
    if isinstance(value,str):return value+'__wrong',True
    if isinstance(value,(dict,list)):
        clone=value.copy()
        for key in (value if isinstance(value,dict) else range(len(value))):
            changed,ok=corrupt(value[key])
            if ok:clone[key]=changed;return clone,True
    return value,False
rows=[]
for path in sorted(ROOT.glob('datasets/*/*.json')):
    p=Problem.load(path);source=(path.parent/'tests'/(p.pid+'.reference.st')).read_text(encoding='utf-8')
    original=local_tests(source,p);assert original.tests_passed==len(p.test_cases),p.pid
    parsed=check_st(source);private={d.name.lower(): 'v3_private_'+d.name for d in parsed.pou.decls if d.section.upper() in ('VAR','VAR_TEMP')}
    tokens,_=tokenize(source);renamed=source
    for token in reversed(tokens):
        if token.kind=='id' and token.value.lower() in private:
            renamed=renamed[:token.col]+private[token.value.lower()]+renamed[token.col+len(token.value):]
    renamed_result=local_tests(renamed,p)
    # Deliberately contradict one actual assertion, leaving the executable program unchanged.
    cases=list(p.test_cases);mutation=None
    for index,case in enumerate(cases):
        for name,value in case.expected.items():
            bad,ok=corrupt(value)
            if not ok:continue
            expected=dict(case.expected);expected[name]=bad;cases[index]=replace(case,expected=expected)
            mutation=dict(case=case.tc_id,output=name);break
        if mutation:break
    assert mutation,p.pid
    negative=local_tests(source,replace(p,test_cases=cases));assert negative.tests_passed<negative.tests_total,p.pid
    rows.append(dict(pid=p.pid,reference_passed=original.tests_passed,total=original.tests_total,
        private_rename_passed=renamed_result.tests_passed,negative_control_rejected=True,mutated_assertion=mutation,
        rename_failures=[c.to_dict() for c in renamed_result.cases if not c.passed]))
print(json.dumps(dict(rows=rows,reference_cases=sum(r['total'] for r in rows),negative_controls=35,private_rename_regressions=[r['pid'] for r in rows if r['private_rename_passed']!=r['total']]),ensure_ascii=False))
