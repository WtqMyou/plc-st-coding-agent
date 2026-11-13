"""Reproducible command-line entrypoints; no online defaults."""
from __future__ import annotations
import argparse
import contextlib
import csv
import hashlib
import json
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path
from .schema import Problem
from .evaluation import atomic_json, evaluate, verification_status
from .platforms import CodesysBackend, OpenPLCBackend
from .providers.mock import MockProvider
from .providers.base import ProviderError
from .portability import PROFILE
from .harness.runner import Solver, solve_problem, summarize

ROOT=Path(__file__).resolve().parents[1]

def problems():
    return [Problem.load(f) for group in ("public","selfmade")
            for f in sorted((ROOT/"datasets"/group).glob("*.json")) if not f.name.startswith("_")]

def reference(p):
    return (ROOT/"datasets"/p.source/"tests"/(p.pid+".reference.st")).read_text(encoding="utf-8")

def config(path):
    return json.loads(Path(path or ROOT/"config.example.json").read_text(encoding="utf-8"))

def doctor(cfg):
    root=Path(cfg["platform_root"])
    return dict(python=sys.version,os=platform.platform(),platform_root=str(root),
        free_gb=round(shutil.disk_usage(root).free/1024**3,2) if root.is_dir() else None,
        models_selected=len(cfg.get("models",[])),live_enabled=cfg.get("live_enabled",False),
        budget_configured=cfg.get("budget_cny") is not None,
        codesys_executable_present=Path(cfg.get("codesys_executable","")).is_file(),
        codesys_template_present=Path(cfg.get("codesys_template","")).is_file(),
        openplc_executable_present=Path(cfg.get("openplc_executable","")).is_file(),
        codex_executable=shutil.which("codex"),expected_problems=len(problems()),
        expected_cases=sum(len(p.test_cases) for p in problems()))

def freeze(out):
    entries=[]
    for p in problems():
        f=ROOT/"datasets"/p.source/(p.pid+".json")
        ref=f.parent/"tests"/(p.pid+".reference.st")
        entries.append(dict(pid=p.pid,json=f.relative_to(ROOT).as_posix(),
            json_sha256=hashlib.sha256(f.read_bytes()).hexdigest(),
            reference=ref.relative_to(ROOT).as_posix(),reference_sha256=hashlib.sha256(ref.read_bytes()).hexdigest(),
            cases=len(p.test_cases),specs=len(p.specs)))
    snapshot=dict(schema_version=2,created_at=time.strftime("%Y-%m-%dT%H:%M:%S"),
                  problems=len(entries),cases=sum(e["cases"] for e in entries),
                  specs=sum(e["specs"] for e in entries),entries=entries)
    atomic_json(out,snapshot)
    return snapshot

def export_summary(out,summary):
    atomic_json(out,summary)
    with out.with_suffix(".csv").open("w",newline="",encoding="utf-8-sig") as f:
        rows=summary if isinstance(summary,list) else [summary]
        keys=sorted({k for row in rows for k,v in row.items() if not isinstance(v,(dict,list))})
        writer=csv.DictWriter(f,fieldnames=keys,extrasaction="ignore")
        writer.writeheader();writer.writerows(rows)

def main(argv=None):
    effective=sys.argv[1:] if argv is None else argv
    if effective and effective[0]=='campaign':
        from .campaign import main as campaign_main
        return campaign_main(effective[1:])
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("command",choices=["doctor","freeze","verify-refs","platform-check","matrix"])
    ap.add_argument("--config",default="")
    ap.add_argument("--out",default="")
    ap.add_argument("--mc",action="store_true")
    ap.add_argument("--mc-seconds",type=float,default=60)
    ap.add_argument("--pid",default="")
    ap.add_argument("--platform",choices=["codesys","openplc","both"],default="both")
    ap.add_argument("--offline",action="store_true")
    ap.add_argument("--resume",action="store_true")
    ap.add_argument("--adapted",action="store_true",help="Separate "+PROFILE+" variant; original results remain separate")
    args=ap.parse_args(argv)
    cfg=config(args.config)
    out=Path(args.out) if args.out else ROOT/"evidence"/(args.command+".json")
    out.parent.mkdir(parents=True,exist_ok=True)
    ps=[p for p in problems() if not args.pid or p.pid==args.pid]
    if not ps:
        ap.error("Unknown problem id")
    if args.command=="doctor":
        d=doctor(cfg);atomic_json(out,d);print(json.dumps(d,ensure_ascii=False,indent=2));return 0
    if args.command=="freeze":
        d=freeze(out);print(f"Frozen {d['problems']} problems / {d['cases']} cases / {d['specs']} specs");return 0
    if args.command=="verify-refs":
        rows=[]
        for p in ps:
            p.mc_max_seconds=args.mc_seconds
            r=evaluate(reference(p),p,model_check=args.mc,timeout_s=args.mc_seconds+2,
                       cache_dir=Path(cfg["platform_root"])/"cache"/"judge")
            row=dict(pid=p.pid,static_compiles=r.compiles,tests_passed=r.tests_passed,
                     tests_total=len(p.test_cases),verification_status=verification_status(r),judge=r.to_dict())
            rows.append(row);atomic_json(out,rows)
            print(p.pid,r.tests_passed,len(p.test_cases),verification_status(r),flush=True)
        export_summary(out,rows)
        return 0 if all(r["static_compiles"] and r["tests_passed"]==r["tests_total"]
                        and (not args.mc or r["verification_status"]=="bounded_pass") for r in rows) else 1
    if args.command=="platform-check":
        backends=[CodesysBackend(cfg),OpenPLCBackend(cfg)]
        backends=[b for b in backends if args.platform in ("both",b.name)]
        rows=[]
        for p in ps:
            for b in backends:
                source=reference(p)
                mapping=None
                if args.adapted:
                    from .portability import adapt
                    candidate_problem,source,mapping=adapt(p,source,b.name)
                else:
                    candidate_problem=p
                r=b.compile(source,candidate_problem)
                rows.append(dict(pid=p.pid,adaptation=mapping,**r.to_dict()))
                atomic_json(out,rows)
                print(b.name,p.pid,r.status,flush=True)
        export_summary(out,rows)
        return 0 if all(r["status"]=="passed" for r in rows) else 1
    if args.command=="matrix":
        from .codex_baseline import CodexProvider,ResponsesGateway
        from .live import Budget,configured_provider,validate_live_config
        summaries=[]
        task_sources={p.pid:reference(p) for p in ps} if args.offline else {}
        if args.adapted:
            from .portability import adapt
            transformed=[]
            for p in ps:
                q,src,_=adapt(p,task_sources.get(p.pid,""),"codesys")
                transformed.append(q)
                if args.offline:task_sources[p.pid]=src
            ps=transformed
        if args.offline:
            model_ids=["fixture-A","fixture-B"]
        else:
            validate_live_config(cfg)  # Before any credential, client or endpoint is used.
            if cfg.get('budget_ledger_path'):
                raise ProviderError('Shared campaign budget requires the campaign entrypoint; legacy matrix cannot create another ledger')
            model_ids=[m["id"] for m in cfg["models"][:2]]
            health=doctor(cfg)
            if not health["codesys_executable_present"] or not health["codesys_template_present"]:
                raise ProviderError("Real experiment requires installed CODESYS and a validated template")
            for model in cfg["models"][:2]:
                if not str(model.get("responses_base_url","")).startswith("https://"):
                    raise ProviderError("Codex baseline requires an explicitly verified HTTPS Responses API endpoint")
            fixture=Problem.from_dict(dict(pid="native-preflight",source="selfmade",difficulty="easy",
                title="Native compiler preflight",requirements="b equals a",
                variables=[dict(name="a",data_type="BOOL",direction="input"),
                           dict(name="b",data_type="BOOL",direction="output")]))
            source="FUNCTION_BLOCK STBenchPreflight\nVAR_INPUT a:BOOL; END_VAR\nVAR_OUTPUT b:BOOL; END_VAR\nb:=a;\nEND_FUNCTION_BLOCK"
            native=CodesysBackend(cfg)
            positive=native.compile(source,fixture)
            negative=native.compile(source.replace("b:=a;","b:=;"),fixture)
            atomic_json(out.parent/"native_preflight.json",{"positive":positive.to_dict(),"negative":negative.to_dict()})
            if positive.status!="passed" or negative.status!="failed":
                raise ProviderError("Native compiler positive/negative preflight failed; no model request was sent")
        ledger=out.parent/"budget_ledger.json"
        for framework in ("custom","codex"):
            for model_id in model_ids:
                records=[]
                log_dir=out.parent/(framework+"_"+model_id)
                cache_scope=hashlib.sha256((str(out.resolve())+"/"+framework+"/"+model_id).encode()).hexdigest()
                group_cache=Path(cfg["platform_root"])/"cache"/"experiment_judges"/cache_scope
                group_started=time.monotonic()
                for p in ps:
                    with contextlib.ExitStack() as stack:
                        if args.offline:
                            if framework=="custom":
                                provider=MockProvider(model=model_id,reference=task_sources[p.pid])
                            else:
                                gateway=stack.enter_context(ResponsesGateway(mock_text=task_sources[p.pid],model=model_id))
                                provider=CodexProvider(gateway,model=model_id,mock=True,
                                    work_root=Path(cfg["platform_root"])/"builds"/"codex")
                            backends=()
                        else:
                            spec=next(m for m in cfg["models"] if m["id"]==model_id)
                            if framework=="custom":
                                provider=configured_provider(cfg,model_id,ledger)
                            else:
                                gateway=stack.enter_context(ResponsesGateway(model=spec["model"],spec=spec,
                                    budget=Budget(ledger,cfg["budget_cny"]),
                                    max_tokens=cfg["limits"]["max_output_tokens"]))
                                provider=CodexProvider(gateway,model=spec["model"],
                                    work_root=Path(cfg["platform_root"])/"builds"/"codex")
                            backends=(CodesysBackend(cfg),)
                        limits=cfg.get("limits",{})
                        solver=Solver(provider,max_iters=limits.get("max_candidates",5),
                            model_check=args.mc or not args.offline,
                            task_seconds=limits.get("task_seconds",600),
                            mc_seconds=limits.get("mc_seconds",60),
                            cache_dir=group_cache,backends=backends)
                        r=solve_problem(p,solver,log_dir=log_dir,resume=args.resume)
                        records.append(r)
                        print(framework,model_id,p.pid,"test-pass" if r.solved else "failed",flush=True)
                summary=summarize(records)|dict(framework=framework,
                    group_wall_seconds=time.monotonic()-group_started,
                    judge_cache_scope=cache_scope,
                    task_profile=PROFILE if args.adapted else "original-v2.1",
                    warning="OFFLINE fixtures; not model performance" if args.offline else "")
                summaries.append(summary);export_summary(out,summaries)
        return 0 if len(summaries)==4 and all(s["solve_rate"]==1 for s in summaries) else 1
    return 2

if __name__=="__main__":
    try:
        raise SystemExit(main())
    except ProviderError as exc:
        print(str(exc),file=sys.stderr)
        raise SystemExit(2)
