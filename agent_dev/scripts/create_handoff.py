"""Build a compact source/evidence handoff; platform installers remain on E:."""
from __future__ import annotations
import collections
import hashlib
import json
import platform
import subprocess
import sys
import time
import zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.cli import freeze,doctor,config,problems,reference
from stbench.portability import adapt, PROFILE
from stbench.evaluation import atomic_json

def read(name,default):
    p=ROOT/name
    return json.loads(p.read_text(encoding="utf-8")) if p.is_file() else default

def main():
    cfg=config("")
    snapshot=freeze(ROOT/"evidence"/"dataset_freeze_v2.1.json")
    n,cases=snapshot["problems"],snapshot["cases"]
    tasks=problems();pids={p.pid for p in tasks}
    judge_hash=hashlib.sha256(b"".join(f.read_bytes() for f in sorted((ROOT/"stbench").rglob("*.py")))).hexdigest()
    health=doctor(cfg)
    atomic_json(ROOT/"evidence"/"environment.json",health)
    acceptance=read("evidence/acceptance/results.json",[])
    matrix=read("evidence/offline_matrix_v2.1/summary.json",[])
    mc=read("evidence/reference_mc_current.json",[])
    reference_tests=read("evidence/reference_tests.json",[])
    checks={"automatic_acceptance":len(acceptance)==6 and all(r["returncode"]==0 for r in acceptance),
        "reference_cases":len(reference_tests)==n and {r['pid'] for r in reference_tests}==pids and
            sum(r["tests_passed"] for r in reference_tests)==cases and all(r['static_compiles'] and
            r['judge']['evidence_metadata']['judge_source_sha256']==judge_hash for r in reference_tests),
        "offline_matrix":len(matrix)==4 and all(r["n"]==n and r["tests_passed"]==cases for r in matrix)}
    records=[f for f in (ROOT/"evidence/offline_matrix_v2.1").glob("*/*.json")]
    checks['matrix_freshness']=len(records)==n*4 and all(
        read(str(f.relative_to(ROOT)),{})['attempts'][0]['judge']['evidence_metadata']['judge_source_sha256']==judge_hash
        for f in records)
    checks['ltl_recorded']=len(mc)==n and {r['pid'] for r in mc}==pids and all(
        r['verification_status'] not in ('not_run','violated','tool_error') and
        r['judge']['evidence_metadata']['judge_source_sha256']==judge_hash for r in mc)
    checks['generator_consistency']=subprocess.run([sys.executable,"-B","-X","utf8",
        "scripts/rebuild_selfmade.py"],cwd=ROOT,capture_output=True,timeout=30).returncode==0
    smoke=read("evidence/integration_smoke.json",[])
    checks["real_platform_integration"]=len(smoke)==9 and all(r["solved"] and
        r["attempts"][0]["verification_status"] not in ("not_run","tool_error") and
        r["attempts"][0]['judge']['evidence_metadata']['judge_source_sha256']==judge_hash and
        set(r['attempts'][0]['platform_results'])=={'codesys','openplc'} for r in smoke)
    for name in ("codesys","openplc"):
        native=read("evidence/"+name+"_adapted.json",[])
        controls=read("evidence/"+name+"_compiler_controls.json",{})
        expected={p.pid:hashlib.sha256(adapt(p,reference(p),name)[1].encode()).hexdigest() for p in problems()}
        checks[name+"_native"]=len(native)==n and {r["pid"] for r in native}==set(expected) and all(
            r["status"]=="passed" and r["source_sha256"]==expected[r["pid"]] for r in native) and controls.get("passed") is True
    atomic_json(ROOT/"evidence"/"handoff_checks.json",checks)
    if not all(checks.values()):
        raise RuntimeError("Pre-work handoff has unfinished acceptance items: "+str([k for k,v in checks.items() if not v]))
    lines=["# 前期验收与交接状态","",
        "真实模型和预算待用户指定；当前未开展付费模型实验。离线 fixture 结果仅证明流水线工作。","",
        "## 自动化与数据","",
        f"- 当前 {n} 题 / {cases} 条用例 / {snapshot['specs']} 条规约；20 公共题与 15 自建题。",
        "- 原有 378 条及新增 57 条用例的输入和 expected 均由哈希回归保护，补充行为测试单列。",
        "- 2026-10-30 更新：整合组员 v1.2；详见二次更新整合说明和增量补丁。",
        f"- 自动验收命令：{sum(r['returncode']==0 for r in acceptance)}/{len(acceptance)} 组通过。",
        "","## 实际平台编译","",
        "| 平台/契约 | 已检查 | 编译通过 | 其他状态 |","|---|---:|---:|---|"]
    for platform_name in ("codesys","openplc"):
        for variant in ("original","adapted"):
            rows=read("evidence/"+platform_name+"_"+variant+".json",[])
            counts=collections.Counter(r["status"] for r in rows)
            lines.append(f"| {platform_name}/{variant} | {len(rows)} | {counts['passed']} | {dict(counts)} |")
    lines+=["","编译证据仅代表本机平台流程。OpenPLC v4 生成 C++ 和运行时上传包；未上传到物理 PLC。",
        "适配版保留原输出断言，但改变了已记录的接口/时间表示；FIFO 是有界 DINT 特化。","",
        "联锁、状态机、批次与新增五类流程题共完成九次端到端闭环冒烟：离线生成→真实双平台编译→功能测试→LTL。",
        "该冒烟的 LTL 上限为 2 秒，只验接口执行；截断和超时不算规约通过。完整规约搜索另表记录。","",
        "## 有界验证","",
        f"本轮已记录 {len(mc)}/{n} 题；状态分布：{dict(collections.Counter(r['verification_status'] for r in mc))}。",
        "深度、输入域、时间及迁移预算见逐题记录。截断、超时、工具错误和未建模项均不作为通过。",
        "","## 四组离线接口验收","",
        "| 框架 | 模拟服务 | 题数 | 用例通过 | 用途 |",
        "|---|---|---:|---:|---|"]
    for row in matrix:
        lines.append(f"| {row['framework']} | {row['model']} | {row['n']} | {row['tests_passed']}/{row['tests_total']} | 离线流程，不是真实模型表现 |")
    lines+=["","## 后续工作","",
        "1. 工艺合理性和最终题目取舍由组内评审确认；当前全量保留 35 题，不擅自替换旧题。",
        "2. 用户指定两个模型、接入方式、价格和预算后，开展真实接口核验。",
        "3. 冻结配置并完整运行四组实验，再按实验协议进行改进和最终复测。",
        "","## 文件与磁盘","",
        "源码与交接包位于课程项目的 finalwork；安装包、平台主体和大构建目录位于 E:\\PLC_Dev。",
        "Windows Installer 和 CODESYS 强制使用的系统缓存/注册项可能位于 C 盘；见平台安装记录。",
        f"当前统一平台契约为 {PROFILE}，旧 portable-frame-v1 和旧实验记录仅供历史追溯。",
        "密钥与本机私有配置不进入交接包。"]
    (ROOT/"docs"/"验收报告.md").write_text("\n".join(lines)+"\n",encoding="utf-8")
    subprocess.run([sys.executable,"-B","-X","utf8",str(ROOT/"scripts/create_update_patch.py")],
                   cwd=ROOT,check=True,timeout=30)
    excluded={"__pycache__",".pytest_cache",".venv","runs"}
    files=[p for p in ROOT.rglob("*") if p.is_file() and not (set(p.relative_to(ROOT).parts)&excluded)
           and p.name not in ("config.local.json",".env") and p.suffix not in (".pyc",".tmp")]
    manifest={"release":"2.1","created_at":time.strftime("%Y-%m-%dT%H:%M:%S"),"python":platform.python_version(),
        "files":[{"path":p.relative_to(ROOT).as_posix(),"bytes":p.stat().st_size,
                  "sha256":hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(files)
                 if p.name!="MANIFEST_v2.json"]}
    atomic_json(ROOT/"MANIFEST_v2.json",manifest)
    package=ROOT.parent/"成员2_Agent前期交接包_v2.1_20261030.zip"
    with zipfile.ZipFile(package,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in sorted(files):
            if p.name!="MANIFEST_v2.json":z.write(p,"agent_dev/"+p.relative_to(ROOT).as_posix())
        z.write(ROOT/"MANIFEST_v2.json","agent_dev/MANIFEST_v2.json")
    print(json.dumps({"package":str(package),"bytes":package.stat().st_size,
                      "sha256":hashlib.sha256(package.read_bytes()).hexdigest()},ensure_ascii=False))

if __name__=="__main__":
    main()
