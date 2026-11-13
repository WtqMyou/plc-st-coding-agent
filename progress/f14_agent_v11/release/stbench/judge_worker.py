"""Private subprocess; stdout is JSON checkpoints, not model-visible feedback."""
import json
import sys
from dataclasses import fields
from .schema import Problem
from .evaluation import local_tests,check_interface
from .st.driver import _attach_model_check, _plain, _compile_errors, StageResult


def emit(r):
    d = r.to_dict()
    d.update({f.name: _plain(getattr(r, f.name)) for f in fields(r) if f.name.startswith("mc_")})
    print(json.dumps(d, ensure_ascii=False), flush=True)


def main():
    job = json.load(sys.stdin)
    p = Problem.from_dict(job["problem"])
    if job.get("stage")=="static":
        ok,errors,summary=_compile_errors(job["code"])
        if ok:
            errors=check_interface(job["code"],p)
            ok=not errors
        emit(StageResult(compiles=ok,compile_errors=errors,tests_total=len(p.test_cases),
                         failure_summary=summary if not ok else ""))
        return
    r = local_tests(job["code"], p)
    emit(r)
    if r.compiles and job["model_check"] and (not job.get('verification_after_tests') or
            r.tests_total > 0 and r.tests_passed == r.tests_total):
        _attach_model_check(job["code"], p, r)
        emit(r)


if __name__ == "__main__":
    main()
