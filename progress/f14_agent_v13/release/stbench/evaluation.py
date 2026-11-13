"""Independent judge. Full results stay here; agents receive an allowlisted view."""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import fields, replace
from pathlib import Path
from typing import Any

from .schema import Problem
from .st.driver import CaseResult, StageResult, verify, verify_sequence
from .st.frontend import compile_st, tokenize
from .st.typecheck import typecheck

ROOT = Path(__file__).resolve().parents[1]
ENGINE_VERSION = "judge-v2.1-fixed-bindings"


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, path)


def result_from_dict(data: dict) -> StageResult:
    names = {f.name for f in fields(StageResult)} - {"cases"}
    r = StageResult(**{k: v for k, v in data.items() if k in names})
    r.cases = [CaseResult(**c) for c in data.get("cases", [])]
    return r


def _norm_type(text: str) -> str:
    return "".join(text.upper().split())


def _batch_clock_error(src: str) -> dict | None:
    """Batch task R5 permits scan counting only. Inspect tokens in type or call context."""
    time_types = {"TIME", "LTIME"}
    timers = {"TON", "TOF", "TP", "TONR"}
    clock_calls = {"CURRENT_TIME", "CURRENT_TOD", "CURRENT_DT", "CURRENT_DATE_AND_TIME",
                   "SYSTIMEGETMS", "SYSTIMEGETUS", "SYSTIMEGETNS"}
    tokens, _ = tokenize(src)
    for i, token in enumerate(tokens):
        name = token.value.upper()
        # The lexer classifies IEC T#.../TIME#... as numeric literals.
        forbidden = token.kind == "num" and name.startswith(("T#", "TIME#", "LT#", "LTIME#"))
        if token.kind in {"kw", "id"}:
            before = tokens[i-1].value.upper() if i else ""
            after = tokens[i+1].value if i+1<len(tokens) else ""
            if before in {":","OF"} and name in time_types | timers:
                forbidden = True
            if after == "(":
                src_type, sep, dst_type = name.partition("_TO_")
                conversion = name in {"TO_TIME", "TO_LTIME"} or (
                    bool(sep) and (src_type in time_types or dst_type in time_types))
                forbidden = forbidden or conversion or name in time_types | timers | clock_calls
        if forbidden:
            return {"code":"E_BATCH_SCAN_CLOCK","line":token.line,
                    "message":f"批次时长要求以扫描拍计数，禁止使用时间类型、计时器或时钟：{token.value}"}
    return None


def check_interface(src: str, problem: Problem) -> list[dict]:
    """Compare declarations, not text/comments; names are IEC case-insensitive."""
    parsed = typecheck(compile_st(src))
    if parsed.pou is None:
        return []
    decls = {d.name.lower(): d for d in parsed.pou.decls
             if d.section.upper() in ("VAR_INPUT", "VAR_OUTPUT", "VAR_IN_OUT")}
    expected = {v.name.lower(): v for v in problem.variables}
    errors = []
    if problem.pid == "self-hard-02":
        diagnostic = _batch_clock_error(src)
        if diagnostic:
            errors.append(diagnostic)
    if parsed.pou.kind.upper()!=problem.target_pou.upper():
        errors.append({"code":"E_POU_KIND","line":parsed.pou.line,"message":"POU 类型与题面不一致"})
    def check_fields(dtype, expected_fields, path, line, seen):
        if not expected_fields:
            return
        base = re.split(r"\bOF\b", dtype, flags=re.I)[-1].strip()
        struct = next((value for key, value in parsed.structs.items() if key.lower() == base.lower()), None)
        if struct is None or not hasattr(struct, "fields"):
            errors.append({"code":"E_INTERFACE_FIELD", "line":line, "message":f"接口 {path} 缺少公开结构体字段声明"})
            return
        if base.lower() in seen:
            errors.append({"code":"E_INTERFACE_FIELD", "line":line, "message":f"接口 {path} 的结构体递归定义不支持"})
            return
        actual = {key.lower():value for key,value in struct.fields.items()}
        wanted = {field.name.lower():field for field in expected_fields}
        for key in sorted(set(actual) | set(wanted)):
            field = wanted.get(key)
            if field is None or key not in actual or _norm_type(actual[key]) != _norm_type(field.data_type):
                errors.append({"code":"E_INTERFACE_FIELD", "line":line,
                    "message":f"公开接口字段 {path}.{key} 缺失、多出或类型不符"})
            else:
                check_fields(actual[key], field.fields, path+"."+field.name, line, seen | {base.lower()})

    for name in sorted(set(decls) | set(expected)):
        d, v = decls.get(name), expected.get(name)
        message = ""
        if d is None:
            message = f"缺少接口变量 {name}"
        elif v is None:
            message = f"出现题面未声明的接口变量 {name}"
        else:
            direction = {"input": "VAR_INPUT", "output": "VAR_OUTPUT", "inout": "VAR_IN_OUT"}[v.direction.value]
            actual_type=d.data_type
            if actual_type.upper() in ("STRING","WSTRING"):
                clean=re.sub(r"\(\*.*?\*\)|//[^\n]*","",src,flags=re.S)
                match=re.search(r"\b"+re.escape(name)+r"\s*:\s*(W?STRING(?:\s*\(\s*\d+\s*\))?)",clean,re.I)
                if match:
                    actual_type=match[1]
            check_fields(actual_type, v.fields, v.name, d.line, set())
            if d.section.upper() != direction or _norm_type(actual_type) != _norm_type(v.data_type):
                message = f"接口 {name} 的类型或方向与题面不一致"
        if message:
            errors.append({"code": "E_INTERFACE", "line": getattr(d, "line", 0), "message": message})
    return errors


def local_tests(src: str, problem: Problem) -> StageResult:
    groups = {}
    for case in problem.test_cases:
        mode = case.mode or problem.case_mode or "single"
        if mode not in ("single", "sequence"):
            raise ValueError(f"Unsupported test mode: {mode}")
        groups.setdefault((case.group, mode), []).append(case)
    if not groups:
        return StageResult(compiles=False, failure_summary="No test cases")
    r = None
    for (_, mode), cases in groups.items():
        part = replace(problem, case_mode=mode, test_cases=cases)
        result = verify_sequence(src, part) if mode == "sequence" else verify(src, part, model_check=False)
        if r is None or not result.compiles:
            r = result
        else:
            r.cases.extend(result.cases)
            r.tests_passed += result.tests_passed
            r.tests_total += result.tests_total
            r.failure_summary = r.failure_summary or result.failure_summary
        if not result.compiles:
            break
    if r.compiles:
        errors = check_interface(src, problem)
        if errors:
            r.compiles = False
            r.compile_errors.extend(errors)
            r.failure_summary = "接口契约检查失败"
            r.tests_passed = 0
    # A compile failure still contributes all task cases to the denominator.
    r.tests_total = len(problem.test_cases)
    return r


def verification_status(r: StageResult) -> str:
    if r.mc_specs_violated:
        return "violated"
    if r.mc_error:
        if r.mc_error.startswith("Unsupported modeling:"):
            return "inconclusive"
        return "timeout" if "timeout" in r.mc_error.lower() else "tool_error"
    if not r.mc_executed:
        return "not_run"
    if r.mc_truncated:
        return "truncated"
    if r.mc_specs_inconclusive:
        return "inconclusive"
    return "bounded_pass" if r.mc_specs_total else "not_applicable"


def feedback_for_agent(r: StageResult) -> str:
    """Never include test notes, expected/actual values, or judge exception bodies."""
    lines = []
    if not r.compiles:
        lines.append("静态检查或接口契约失败：")
        for d in r.compile_errors[:5]:
            lines.append(f"第 {d.get('line', 0)} 行 [{d.get('code', 'E')}] {d.get('message', '')}")
    else:
        lines.append(f"自动测试：{r.tests_passed}/{r.tests_total}。")
        for c in [c for c in r.cases if not c.passed][:6]:
            names = ", ".join(sorted(c.expected)) or "相关输出"
            kind = "运行超时" if "超时" in c.message else ("运行期错误" if "运行期" in c.message else "行为不匹配")
            lines.append(f"用例 {c.tc_id}，模式 {c.mode}，{kind}，请检查 {names}。")
    for platform, item in r.platform_results.items():
        if item["status"] != "passed":
            lines.append(f"真实平台 {platform}：{item['status']}。")
            # Platform diagnostics are public compiler output, never test assertions.
            lines.extend(item.get("diagnostics", [])[:5])
    status = verification_status(r)
    lines.append(f"LTL 检查：{status}。")
    for v in r.mc_violations[:3]:
        lines.append(f"规约 {v['id']} 被违反，位置 {v.get('at')}，公式 {v['formula']}。")
    return "\n".join(lines)


def evaluate(src: str, problem: Problem, *, model_check: bool = True,
             cache_dir: Path | None = None, timeout_s: float = 60.0,
             backends: tuple = (), task_remaining_s: float | None = None,
             verification_after_tests: bool = False) -> StageResult:
    """Hard process timeout includes parsing, initial input enumeration and judging."""
    task_deadline=time.monotonic()+task_remaining_s if task_remaining_s is not None else None
    payload = {"code": src, "problem": problem.to_dict(), "model_check": model_check,
               "verification_after_tests": verification_after_tests}
    judge_hash = hashlib.sha256()
    for f in sorted((ROOT / "stbench").rglob("*.py")):
        if "__pycache__" not in str(f):
            judge_hash.update(f.read_bytes())
    key = hashlib.sha256((judge_hash.hexdigest() + json.dumps(
        dict(payload=payload,hard_timeout_seconds=timeout_s), sort_keys=True)).encode()).hexdigest()
    path = cache_dir / (key + ".json") if cache_dir else None
    metadata={"judge_version":ENGINE_VERSION,"judge_source_sha256":judge_hash.hexdigest(),
        "source_sha256":hashlib.sha256(src.encode()).hexdigest(),
        "problem_sha256":hashlib.sha256(json.dumps(problem.to_dict(),sort_keys=True).encode()).hexdigest(),
        "mc_timeout_seconds":timeout_s,"model_check_requested":model_check,
        "mc_fixed_input_domains":{n:problem.mc_inputs.get(n,[]) for n in problem.mc_fixed_inputs}}
    native_results={}
    if backends:
        # A bounded static worker gates the real compiler. Functional tests and
        # model checking run only after all requested native compilers pass.
        static_payload=payload|{"stage":"static","model_check":False}
        try:
            proc=subprocess.run([sys.executable,"-B","-X","utf8","-m","stbench.judge_worker"],
                cwd=ROOT,input=json.dumps(static_payload),capture_output=True,text=True,encoding="utf-8",
                timeout=max(.05,min(timeout_s,task_deadline-time.monotonic() if task_deadline else timeout_s)))
            checkpoints=[json.loads(line) for line in proc.stdout.splitlines() if line.startswith("{")]
            static=result_from_dict(checkpoints[-1]) if checkpoints and proc.returncode==0 else StageResult(
                tests_total=len(problem.test_cases),mc_error="Static judge tool_error")
        except subprocess.TimeoutExpired:
            static=StageResult(tests_total=len(problem.test_cases),mc_error="Static judge timeout")
        static.evidence_metadata=metadata
        if not static.compiles:
            static.platform_results={b.name:{"platform":b.name,"status":"not_run",
                "diagnostics":["Static or interface gate failed"]} for b in backends}
            return static
        for backend in backends:
            original_timeout=backend.timeout
            remaining=task_deadline-time.monotonic() if task_deadline else original_timeout
            if remaining<=0:
                native_results[backend.name]={"platform":backend.name,"status":"timeout",
                    "diagnostics":["Task deadline reached before native compilation"]}
                continue
            try:
                backend.timeout=min(original_timeout,remaining)
                native_results[backend.name]=backend.compile(src,problem).to_dict()
            finally:
                backend.timeout=original_timeout
        if any(v["status"]!="passed" for v in native_results.values()):
            static.platform_results=native_results
            static.failure_summary="Native compilation did not pass; functional tests and LTL not run"
            return static
    if task_deadline:
        timeout_s=min(timeout_s,task_deadline-time.monotonic())
        if timeout_s<=0:
            result=StageResult(compiles=True,tests_total=len(problem.test_cases),mc_error="Task timeout")
            result.platform_results=native_results;result.evidence_metadata=metadata
            return result
    if path and path.is_file():
        result = result_from_dict(json.loads(path.read_text(encoding="utf-8")))
        result.evidence_metadata=dict(result.evidence_metadata,cache_hit=True)
    else:
        env = dict(os.environ, PYTHONUTF8="1", PYTHONDONTWRITEBYTECODE="1")
        proc = subprocess.Popen([sys.executable, "-B", "-X", "utf8", "-m", "stbench.judge_worker"],
                                cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, encoding="utf-8", env=env)
        timed_out = False
        try:
            out, err = proc.communicate(json.dumps(payload), timeout=max(.05, timeout_s))
        except subprocess.TimeoutExpired:
            timed_out = True
            proc.kill()
            out, err = proc.communicate()
        snapshots = []
        for line in out.splitlines():
            try:
                snapshots.append(json.loads(line))
            except ValueError:
                continue
        if snapshots:
            result = result_from_dict(snapshots[-1])
        else:
            result = StageResult(compiles=False, tests_total=len(problem.test_cases),
                                 failure_summary="Judge process failed",
                                 mc_error="Judge timeout" if timed_out else "Judge tool_error")
        if timed_out:
            result.mc_executed = model_check
            result.mc_error = "Judge timeout"
            result.mc_truncated = True
        elif proc.returncode:
            result.mc_error = "Judge tool_error: " + err[-1800:]
        result.evidence_metadata=result.evidence_metadata|metadata|{"cache_hit":False}
        if path and not timed_out and not result.mc_error:
            atomic_json(path, result.to_dict() | {"mc_executed": result.mc_executed,
                        **{f.name: getattr(result, f.name) for f in fields(StageResult) if f.name.startswith("mc_")}})
    result.platform_results=native_results
    return result
