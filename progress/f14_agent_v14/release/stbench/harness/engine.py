"""Bounded agent loop. Private judge records and model-visible feedback are separate."""
from __future__ import annotations
import hashlib
import json
import math
import time
from dataclasses import asdict, dataclass, field, fields
from pathlib import Path
from ..providers.base import Provider, ProviderError, extract_code
from ..evaluation import atomic_json, evaluate, feedback_for_agent, verification_status
from .prompts import PROMPT_VERSION, build_system_prompt, build_task_prompt

@dataclass
class Attempt:
    idx: int
    code: str
    compiles: bool
    tests_passed: int
    tests_total: int
    feedback: str = ""
    prompt_tokens: int = 0
    completion_tokens: int = 0
    latency_s: float = 0.
    provider_error: str = ""
    verification_status: str = "not_run"
    platform_results: dict = field(default_factory=dict)
    code_hash: str = ""
    judge: dict = field(default_factory=dict)
    cost_cny: float = 0.
    actual_model: str = ""

    @property
    def solved(self):
        return (self.compiles and self.tests_total > 0 and self.tests_passed == self.tests_total
                and not self.provider_error and all(v["status"] == "passed" for v in self.platform_results.values()))
    @property
    def fully_verified(self):
        return self.solved and self.verification_status in ("bounded_pass", "not_applicable")
    def to_dict(self):
        return asdict(self) | {"solved": self.solved, "fully_verified": self.fully_verified}

@dataclass
class RunRecord:
    pid: str
    model: str
    provider: str
    setting: str
    max_iters: int
    attempts: list[Attempt] = field(default_factory=list)
    started_at: float = field(default_factory=time.time)
    finished_at: float = 0.
    error: str = ""
    stop_reason: str = ""
    run_signature: str = ""
    experiment_kind: str = "offline_simulation"
    tests_total: int = 0
    request_window_seconds: float = 0.

    def add(self, a):
        self.attempts.append(a)
        self.finished_at = time.time()
    @property
    def best(self):
        return max(self.attempts, key=lambda a: (a.fully_verified, a.solved,
                   sum(v["status"]=="passed" for v in a.platform_results.values()),
                   a.compiles, a.tests_passed, a.verification_status!="violated", -a.idx), default=None)
    @property
    def solved(self):
        return bool(self.best and self.best.solved)
    @property
    def first_try(self):
        return bool(self.attempts and self.attempts[0].solved)
    @property
    def compile_rate(self):
        return sum(a.compiles for a in self.attempts)/len(self.attempts) if self.attempts else 0.
    @property
    def total_tokens(self):
        return sum(a.prompt_tokens+a.completion_tokens for a in self.attempts)
    @property
    def total_latency_s(self):
        return sum(a.latency_s for a in self.attempts)
    def to_dict(self):
        return asdict(self) | dict(prompt_version=PROMPT_VERSION, solved=self.solved,
               first_try=self.first_try, best_attempt=self.best.idx if self.best else None,
               fully_verified=bool(self.best and self.best.fully_verified),
               compile_rate=self.compile_rate, total_tokens=self.total_tokens,
               total_latency_s=self.total_latency_s, n_attempts=len(self.attempts),
               attempts=[a.to_dict() for a in self.attempts])
    def save(self, path):
        atomic_json(path, self.to_dict())
    @classmethod
    def load(cls, path):
        d=json.loads(path.read_text(encoding="utf-8"))
        r=cls(**{f.name:d[f.name] for f in fields(cls) if f.name in d and f.name!="attempts"})
        r.attempts=[Attempt(**{f.name:a[f.name] for f in fields(Attempt) if f.name in a}) for a in d["attempts"]]
        return r

class Solver:
    def __init__(self, provider, max_iters=5, system_prompt=None, *, include_ltl=True,
                 model_check=True, task_seconds=600, mc_seconds=60, cache_dir=None,
                 backends=(), evaluator=None, defer_budget_repairs=False, request_window_seconds=0.,
                 verification_after_tests=False):
        if (isinstance(request_window_seconds, bool) or not isinstance(request_window_seconds, (int, float))
                or not math.isfinite(request_window_seconds) or request_window_seconds < 0):
            raise ValueError('Request window must be a finite nonnegative number of seconds')
        self.provider=provider
        self.request_window_seconds=request_window_seconds
        self.request_timeout_seconds=provider.timeout
        self.verification_after_tests=verification_after_tests
        if request_window_seconds and request_window_seconds < self.request_timeout_seconds:
            raise ValueError('Request window must cover the configured provider timeout')
        self.max_iters=max(1,max_iters)
        self.system_prompt=system_prompt or build_system_prompt()
        self.include_ltl=include_ltl
        self.model_check=model_check
        self.task_seconds=task_seconds
        self.mc_seconds=mc_seconds
        self.cache_dir=cache_dir
        self.backends=backends
        self.evaluator=evaluator
        self.defer_budget_repairs=defer_budget_repairs
        root=Path(__file__).resolve().parents[2]
        self.code_version=hashlib.sha256(b"".join(f.read_bytes() for f in sorted((root/"stbench").rglob("*.py")))).hexdigest()
    @property
    def setting(self):
        return "iterative" if self.max_iters>1 else "one-shot"

def _verify(problem, code):
    return evaluate(code,problem)

def _feedback_from(result, issue=""):
    return (issue+"\n" if issue else "")+feedback_for_agent(result)

def solve_problem(problem, solver, max_iters=None, log_dir=None, resume=False, active_elapsed_before=0.):
    iters=solver.max_iters if max_iters is None else max(1,max_iters)
    signature=hashlib.sha256(json.dumps(dict(problem=problem.to_dict(),model=solver.provider.model,
        provider=solver.provider.name,prompt=PROMPT_VERSION,system=solver.system_prompt,
        include_ltl=solver.include_ltl,model_check=solver.model_check,iters=iters,
        task_seconds=solver.task_seconds,mc_seconds=solver.mc_seconds,
        defer_budget_repairs=solver.defer_budget_repairs,
        request_window_seconds=solver.request_window_seconds,request_timeout_seconds=solver.request_timeout_seconds,
        verification_after_tests=solver.verification_after_tests,
        code_version=solver.code_version,
        offline_fixture=hashlib.sha256(str(getattr(solver.provider,"reference",
            getattr(getattr(solver.provider,"gateway",None),"mock_text",""))).encode()).hexdigest(),
        platforms=[b.identity() for b in solver.backends]),sort_keys=True).encode()).hexdigest()
    rec=RunRecord(problem.pid,solver.provider.model,solver.provider.name,solver.setting,iters,
                  run_signature=signature,experiment_kind="offline_simulation"
                  if solver.provider.name in ("mock","codex-mock") else "live",
                  tests_total=len(problem.test_cases),request_window_seconds=solver.request_window_seconds)
    path=log_dir/(problem.pid+".json") if log_dir else None
    if resume and path and path.is_file():
        rec=RunRecord.load(path)
        if rec.run_signature!=signature:
            raise ValueError("Resume rejected: dataset, model, prompt or limits changed")
        if len(rec.attempts)>=iters:
            return rec
        if rec.stop_reason and rec.stop_reason not in ('provider_error','budget_exhausted','repair_budget_deferred'):
            return rec
        rec.error='';rec.stop_reason=''
    started=time.monotonic()
    previous_elapsed=max(rec.total_latency_s,active_elapsed_before)
    seen={a.code_hash for a in rec.attempts}
    task=build_task_prompt(problem,include_ltl=solver.include_ltl)
    if problem.provenance.get("release_contract") != "STBench-F1.4":
        task+="\n实现检查清单：接口匹配；复位/安全优先；状态保持；边沿先计算再更新历史；数组边界；扫描周期。"
    for i in range(len(rec.attempts),iters):
        remaining=solver.task_seconds-previous_elapsed-(time.monotonic()-started)
        if remaining<=0:
            rec.stop_reason="task_timeout"
            break
        messages=[dict(role="system",content=solver.system_prompt),dict(role="user",content=task)]
        if rec.attempts:
            if rec.best.code:
                messages.append(dict(role="assistant",content=rec.best.code))
            messages.append(dict(role="user",content=rec.attempts[-1].feedback[:4000]+"\n修复并返回完整代码，保持题面接口。"))
        # Include prompt preparation and prior platform/framework time before sending.
        # A local stop creates neither a paid request nor a fabricated failed candidate.
        remaining=solver.task_seconds-previous_elapsed-(time.monotonic()-started)
        if remaining<=0:
            rec.stop_reason='task_timeout'
            break
        if remaining<solver.request_window_seconds:
            rec.stop_reason='insufficient_request_window'
            break
        t0=time.monotonic()
        try:
            solver.provider.timeout=min(solver.request_timeout_seconds,remaining)
            response=solver.provider.generate(messages)
            code=extract_code(response.text)
            h=hashlib.sha256(code.encode()).hexdigest()
            usage=response.usage
            if h in seen:
                rec.add(Attempt(i,code,False,0,len(problem.test_cases),code_hash=h,
                    prompt_tokens=usage.get("prompt_tokens",0),completion_tokens=usage.get("completion_tokens",0),
                    latency_s=time.monotonic()-t0,feedback="候选重复，终止无效循环。",
                    cost_cny=getattr(response,"cost_cny",0.),actual_model=response.model))
                rec.stop_reason="repeated_candidate"
                break
            seen.add(h)
            remaining=solver.task_seconds-previous_elapsed-(time.monotonic()-started)
            if remaining<=0:
                rec.stop_reason="task_timeout"
                rec.add(Attempt(i,code,False,0,len(problem.test_cases),code_hash=h,
                    prompt_tokens=usage.get("prompt_tokens",0),completion_tokens=usage.get("completion_tokens",0),
                    latency_s=time.monotonic()-t0,cost_cny=getattr(response,"cost_cny",0.),
                    actual_model=response.model))
                break
            r=(solver.evaluator(problem,code) if solver.evaluator else evaluate(code,problem,
                model_check=solver.model_check,verification_after_tests=solver.verification_after_tests,
                timeout_s=min(remaining,solver.mc_seconds),
                cache_dir=solver.cache_dir,backends=solver.backends,task_remaining_s=remaining))
            rec.add(Attempt(i,code,r.compiles,r.tests_passed,len(problem.test_cases),
                feedback=_feedback_from(r),prompt_tokens=usage.get("prompt_tokens",0),
                completion_tokens=usage.get("completion_tokens",0),latency_s=time.monotonic()-t0,
                code_hash=h,verification_status=verification_status(r),
                platform_results=r.platform_results,judge=r.to_dict(),cost_cny=getattr(response,"cost_cny",0.),
                actual_model=response.model))
            if rec.attempts[-1].fully_verified:
                rec.stop_reason="verified"
                break
            if rec.attempts[-1].solved and verification_status(r) in ("timeout","truncated","inconclusive","tool_error","not_run"):
                rec.stop_reason="tests_passed_verification_"+verification_status(r)
                break
        except ProviderError as exc:
            rec.error=str(exc)
            if rec.error.startswith('Budget coverage guard'):
                # No request was sent: keep its denominator, but do not invent a candidate.
                rec.stop_reason='repair_budget_deferred' if solver.defer_budget_repairs and rec.attempts else 'budget_exhausted'
                break
            rec.stop_reason="provider_error"
            receipt=getattr(solver.provider,"last_receipt",{})
            rec.add(Attempt(i,"",False,0,len(problem.test_cases),provider_error=str(exc),latency_s=time.monotonic()-t0,
                cost_cny=getattr(solver.provider,"last_charge",0.),actual_model=receipt.get("model",""),
                prompt_tokens=receipt.get("prompt_tokens",0),completion_tokens=receipt.get("completion_tokens",0)))
            if (rec.error.startswith('Generation incomplete/empty:') and receipt.get('model') and
                receipt.get('finish_reason') in ('length','incomplete') and i+1<iters):
                rec.attempts[-1].feedback='上次生成在已设输出上限处截断，未获得完整候选。请使用简洁实现，避免冗长注释或重复代码，并完整输出功能块及必要类型声明。'
                rec.error='';rec.stop_reason=''
                continue
            break
        finally:
            if path:
                rec.save(path)
    rec.stop_reason=rec.stop_reason or "max_candidates"
    rec.finished_at=time.time()
    if path:
        rec.save(path)
    return rec

def solve_suite(problems,solver,max_iters=None,log_dir=None,skip_done=False):
    return [solve_problem(p,solver,max_iters,log_dir,resume=skip_done) for p in problems]

def summarize(records):
    n=len(records)
    if not n:
        return {"n":0}
    best=[r.best for r in records]
    total=sum(r.tests_total or (r.best.tests_total if r.best else 0) for r in records)
    passed=sum(a.tests_passed for a in best if a)
    native={}
    for name in sorted({k for a in best if a for k in a.platform_results}):
        def ok(a):
            return bool(a and a.platform_results.get(name,{}).get("status")=="passed")
        native[name]=dict(first_compile_rate=sum(ok(r.attempts[0] if r.attempts else None) for r in records)/n,
                          final_compile_rate=sum(ok(a) for a in best)/n,
                          statuses={s:sum(bool(a and a.platform_results.get(name,{}).get("status")==s) for a in best)
                                    for s in ("passed","failed","timeout","unavailable","tool_error","not_run")})
    return dict(n=n,model=records[0].model,provider=records[0].provider,setting=records[0].setting,
        experiment_kind=records[0].experiment_kind,solve_rate=sum(r.solved for r in records)/n,
        first_try_rate=sum(r.first_try for r in records)/n,
        compile_rate=sum(bool(a and a.compiles) for a in best)/n,
        compile_rate_definition="task-level local static pass; native compilation is separate",
        first_static_compile_rate=sum(bool(r.attempts and r.attempts[0].compiles) for r in records)/n,
        native_compilation=native,tests_passed=passed,tests_total=total,test_case_pass_rate=passed/total if total else 0,
        verification_statuses={s:sum(bool(a and a.verification_status==s) for a in best)
          for s in ("bounded_pass","violated","timeout","truncated","inconclusive","tool_error","not_run")},
        avg_iters=sum(len(r.attempts) for r in records)/n,total_tokens=sum(r.total_tokens for r in records),
        total_latency_s=sum(r.total_latency_s for r in records),
        total_cost_cny=sum(a.cost_cny for r in records for a in r.attempts),
        cost_definition="Confirmed returned charges; failed live calls may retain unknown reserved charges in budget_ledger.json",
        cost_unknown_attempts=sum(bool(a.provider_error) and not a.actual_model for r in records if r.experiment_kind=="live" for a in r.attempts),
        known_incomplete_attempts=sum(a.provider_error.startswith('Generation incomplete/empty:') and bool(a.actual_model)
            for r in records for a in r.attempts),
        budget_stopped_tasks=sum(r.stop_reason=='budget_exhausted' for r in records),
        request_window_stopped_tasks=sum(r.stop_reason=='insufficient_request_window' for r in records),
        errors=sum(bool(r.error) for r in records))
