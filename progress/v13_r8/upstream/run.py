"""Offline functional and finite-trace checks on the 13 supplied references."""
from collections import Counter, defaultdict
import json
from pathlib import Path
from trace_check import inspect
from stbench.evaluation import local_tests
from stbench.schema import Problem

root = Path(__file__).resolve().parent
mutations = {
    "public-easy-04": ("validMs >= DebounceMs", "validMs > DebounceMs"),
    "self-hard-04": (" OR (need > prevNeed)", ""),
    "self-medium-03": ("IF obstacle THEN\n    state := 3;", "IF obstacle THEN\n    state := 0;"),
}
results = []
files = sorted(root.glob("datasets/*/*.json"))
assert len(files) == 13, "Expected the 13 confirmation-package problems"
for path in files:
    d = json.loads(path.read_text(encoding="utf8"))
    src = (path.parent/"tests"/(path.stem+".reference.st")).read_text(encoding="utf8")
    groups = defaultdict(list)
    for c in d["test_cases"]:
        assert c["expected"], (path.stem, c["tc_id"])
        groups[c.get("mode") or d.get("case_mode") or "single"].append(c)
    passed = 0
    rejected = []
    for mode, cases in groups.items():
        base = mode.split(":", 1)[0]
        test = Problem.from_dict({**d, "case_mode":base, "test_cases":[{**c,"mode":base} for c in cases]})
        run = local_tests(src,test)
        if not run.compiles or run.tests_passed != len(cases):
            print(path.stem,mode,run.failure_summary,flush=True)
        passed += run.tests_passed
        if path.stem in mutations:
            original, wrong = mutations[path.stem]
            assert src.count(original)==1
            mutant = local_tests(src.replace(original,wrong),test)
            assert mutant.compiles, mutant.failure_summary
            if mutant.tests_passed < len(cases):
                rejected.append(mode)
    n = len(d["test_cases"])
    rows = inspect(path)[1] if passed == n else []
    counts = Counter(r["status"] for r in rows)
    print(path.stem,passed,n,counts,flush=True)
    if path.stem in mutations and not rejected:
        raise RuntimeError(f"{path.stem}: incorrect implementation escaped detection")
    results.append(dict(pid=path.stem,passed=passed,total=n,verdicts=counts,mutant_rejected_by=rejected,issues=[
        r for r in rows if r["status"]!="hold" or r.get("non_interface_names")]))
(root/"results.json").write_text(json.dumps(results,indent=2,ensure_ascii=False),encoding="utf8")
raise SystemExit(int(any(r["passed"]!=r["total"] or r["issues"] for r in results)))
