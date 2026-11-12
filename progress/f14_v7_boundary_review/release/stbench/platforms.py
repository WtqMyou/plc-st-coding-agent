"""Actual native compilers. Unavailable/timeout/tool errors are never passes."""
from __future__ import annotations
import hashlib
import json
import os
import re
import subprocess
import time
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path
from .evaluation import atomic_json

ROOT=Path(__file__).resolve().parents[1]

@dataclass
class CompileResult:
    platform: str
    status: str
    diagnostics: list = field(default_factory=list)
    returncode: int | None = None
    elapsed_s: float = 0.
    artifact_dir: str = ""
    source_sha256: str = ""
    platform_identity: dict = field(default_factory=dict)
    def to_dict(self):
        return asdict(self)


def split_st(src):
    """Extract complete DUT blocks and the POU header/declarations/body losslessly."""
    clean=re.sub(r"\(\*.*?\*\)|//[^\n]*","",src,flags=re.S)
    type_pattern=r"(?:\{\s*attribute\s+'(?:strict|qualified_only)'\s*\}\s*)*\bTYPE\s+.*?\bEND_TYPE\b"
    types=re.findall(type_pattern,clean,flags=re.I|re.S)
    clean=re.sub(type_pattern,"",clean,flags=re.I|re.S)
    header=re.search(r"\b(FUNCTION_BLOCK|PROGRAM|FUNCTION)\s+(\w+)(?:[ \t]*:[ \t]*[A-Za-z_]\w*(?:\(\d+\))?)?",clean,re.I)
    if not header:
        raise ValueError("Missing POU header")
    end=re.search(r"\bEND_"+header[1]+r"\b",clean,re.I)
    if not end:
        raise ValueError("Missing POU terminator")
    middle=clean[header.end():end.start()]
    declaration_end=0
    for m in re.finditer(r"\bEND_VAR\b\s*;?",middle,re.I):
        declaration_end=m.end()
    return dict(name=header[2],kind=header[1].upper(),types=types,
                declaration=header[0]+"\n"+middle[:declaration_end],
                implementation=middle[declaration_end:].strip())


class Backend:
    name="native"
    def __init__(self,config):
        self.config=config
        self.root=Path(config.get("platform_root","E:/PLC_Dev"))
        self.timeout=config.get("limits",{}).get("compile_seconds",120)
    def identity(self):
        path=Path(self.config.get(self.name+"_executable",""))
        inputs={"codesys":[ROOT/"scripts"/"codesys_build.py",ROOT/"stbench"/"platforms.py",Path(self.config.get("codesys_template",""))],
                "openplc":[ROOT/"stbench"/"openplc_project.py"]}.get(self.name,[])
        return dict(platform=self.name,executable=str(path),
                    size=path.stat().st_size if path.is_file() else None,
                    mtime=path.stat().st_mtime_ns if path.is_file() else None,
                    compile_inputs_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None for p in inputs},
                    target=self.config.get(self.name+"_target"),
                    profile=self.config.get(self.name+"_profile"))
    def run(self,args,cwd):
        remaining=min(self.timeout,getattr(self,"_compile_deadline",time.monotonic()+self.timeout)-time.monotonic())
        if remaining<=0:
            return None,"","Native compilation deadline reached"
        env=dict(os.environ,TEMP=str(self.root/"cache"),TMP=str(self.root/"cache"))
        # Files avoid an unbounded communicate() when a descendant keeps stdout open.
        tag=uuid.uuid4().hex[:10];outpath=Path(cwd)/('process_'+tag+'.stdout.log');errpath=Path(cwd)/('process_'+tag+'.stderr.log')
        deadline=time.monotonic()+remaining;timed_out=False
        with outpath.open('xb') as stdout,errpath.open('xb') as stderr:
            p=subprocess.Popen(args,cwd=cwd,stdout=stdout,stderr=stderr,env=env,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
            cleanup_reserve=min(5,remaining*.7)
            try:p.wait(timeout=max(.01,deadline-time.monotonic()-cleanup_reserve))
            except subprocess.TimeoutExpired:
                timed_out=True
                if os.name=='nt':
                    try:subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],
                        stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=max(.01,min(3,deadline-time.monotonic())))
                    except (OSError,subprocess.TimeoutExpired):pass
                if p.poll() is None:
                    p.kill()
                    try:p.wait(timeout=max(.01,deadline-time.monotonic()))
                    except subprocess.TimeoutExpired:pass
        out=outpath.read_text(encoding='utf-8',errors='replace');err=errpath.read_text(encoding='utf-8',errors='replace')
        return (None if timed_out else p.returncode),out,err
    def compile(self,src,problem):
        t0=time.monotonic()
        result=CompileResult(self.name,"unavailable",source_sha256=hashlib.sha256(src.encode()).hexdigest(),
                             platform_identity=self.identity())
        exe=Path(self.config.get(self.name+"_executable",""))
        if not exe.is_file():
            result.diagnostics=["未发现配置的真实平台可执行文件"]
            return result
        work=self.root/"builds"/self.name/(problem.pid+"_"+uuid.uuid4().hex[:10])
        work.mkdir(parents=True,exist_ok=False)
        result.artifact_dir=str(work)
        (work/"candidate.st").write_text(src,encoding="utf-8")
        try:
            self._compile_deadline=t0+self.timeout
            self._compile(exe,work,src,result)
        except (OSError,ValueError,KeyError,TypeError) as exc:
            result.status="tool_error"
            result.diagnostics=[type(exc).__name__+": "+str(exc)[:500]]
        result.elapsed_s=time.monotonic()-t0
        atomic_json(work/"result.json",result.to_dict())
        return result


class CodesysBackend(Backend):
    name="codesys"
    def _compile(self,exe,work,src,result):
        template=Path(self.config.get("codesys_template",""))
        if not template.is_file():
            result.status="unavailable"
            result.diagnostics=["缺少带设备和 Application 的 CODESYS 模板工程"]
            return
        job=split_st(src)|dict(template=str(template.resolve()),project=str(work/"candidate.project"),
                              result=str(work/"codesys_result.json"),nonce=uuid.uuid4().hex)
        atomic_json(work/"job.json",job)
        args=[str(exe),"--noUI","--profile="+self.config["codesys_profile"],
              "--runscript="+str(ROOT/"scripts"/"codesys_build.py"),
              "--scriptargs="+str(work/"job.json")]
        if os.name=="nt":
            values=[str(exe),self.config["codesys_profile"],str(ROOT/"scripts"/"codesys_build.py"),str(work/"job.json")]
            if any('"' in value or "\n" in value for value in values):
                raise ValueError("Invalid quote in CODESYS configuration")
            args='"'+values[0]+'" --noUI --culture=en --profile="'+values[1]+'" --runscript="'+values[2]+'" --scriptargs:"'+values[3]+'"'
        rc,out,err=self.run(args,work)
        (work/"stdout.log").write_text(out,encoding="utf-8")
        (work/"stderr.log").write_text(err,encoding="utf-8")
        result.returncode=rc
        if rc is None:
            result.status="timeout"
        elif not (work/"codesys_result.json").is_file():
            result.status="tool_error"
            result.diagnostics=["CODESYS 未生成本次运行的结果文件；检查 Scripting 组件和 profile"]
        else:
            report=json.loads((work/"codesys_result.json").read_text(encoding="utf-8-sig"))
            if report.get("nonce")!=job["nonce"]:
                raise ValueError("CODESYS result nonce mismatch")
            result.status=report["status"] if rc==0 else "tool_error"
            result.diagnostics=report.get("diagnostics",[])


class OpenPLCBackend(Backend):
    name="openplc"
    def _compile(self,exe,work,src,result):
        cli=[str(exe),"--cli","--user-data",str(self.root/"cache"/"openplc")]
        rc,out,err=self.run(cli+["create","candidate","--path",str(work),"--language","st"],work)
        (work/"create.log").write_text(out+"\n"+err,encoding="utf-8")
        if rc!=0:
            result.status="timeout" if rc is None else "tool_error"
            result.diagnostics=["OpenPLC project creation failed; see create.log"]
            return
        project=work/"candidate"
        # Version-pinned project writer is validated against an actual CLI-created template.
        from .openplc_project import write_candidate
        write_candidate(project,src)
        rc,out,err=self.run(cli+["compile",str(project),"--target",
                               self.config.get("openplc_target","OpenPLC Runtime v4")],work)
        (work/"stdout.log").write_text(out,encoding="utf-8")
        (work/"stderr.log").write_text(err,encoding="utf-8")
        result.returncode=rc
        result.status="timeout" if rc is None else ("passed" if rc==0 else ("failed" if rc==4 else "tool_error"))
        result.diagnostics=(err or out).splitlines()[-12:] if rc!=0 else []
