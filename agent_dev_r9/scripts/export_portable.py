"""Export reviewable portable contracts; never alter original task files."""
import hashlib
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.cli import problems,reference
from stbench.portability import adapt,PROFILE
from stbench.evaluation import atomic_json,local_tests


def main():
    out=ROOT/"platform_projects"/PROFILE
    rows=[]
    for p in problems():
        q,src,mapping=adapt(p,reference(p),"codesys")
        r=local_tests(src,q)
        if not r.all_tests_passed:raise RuntimeError(p.pid+": adapted behavior differs")
        target=out/p.pid
        target.mkdir(parents=True,exist_ok=True)
        atomic_json(target/"problem.json",q.to_dict())
        (target/"reference.st").write_text(src,encoding="utf-8")
        mapping.update(original_source_sha256=hashlib.sha256(reference(p).encode()).hexdigest(),
                       tests_passed=r.tests_passed,tests_total=r.tests_total,
                       original_expected_sha256=hashlib.sha256(str([c.expected for c in p.test_cases]).encode()).hexdigest())
        rows.append(mapping)
    atomic_json(out/"mapping.json",rows)
    print("Exported",len(rows),"contracts /",sum(r["tests_total"] for r in rows),"cases")


if __name__=="__main__":main()
