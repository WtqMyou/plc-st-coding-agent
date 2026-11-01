"""Collect three small real projects and compiler control logs for handoff."""
import json
import shutil
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.evaluation import atomic_json


def main():
    rows=[]
    for platform in ("codesys","openplc"):
        evidence=ROOT/"evidence"/(platform+"_adapted.json")
        if not evidence.is_file():continue
        results=json.loads(evidence.read_text(encoding="utf-8"))
        for pid in ("self-easy-02","self-medium-03","self-hard-02", "self-hard-05", "self-hard-06",
                    "self-hard-07", "self-medium-05", "self-medium-06"):
            item=next(r for r in results if r["pid"]==pid)
            if item["status"]!="passed":continue
            src=Path(item["artifact_dir"])
            dst=ROOT/"platform_projects"/platform/pid
            shutil.copytree(src,dst,dirs_exist_ok=True,
                ignore=shutil.ignore_patterns("*.cache","*.opt","*.bak","__pycache__"))
            rows.append(dict(platform=platform,pid=pid,source_sha256=item["source_sha256"],
                original_artifact_dir=str(src),packaged_project=str(dst.relative_to(ROOT))))
        controls=ROOT/"evidence"/(platform+"_compiler_controls.json")
        if controls.is_file():
            for label,item in json.loads(controls.read_text(encoding="utf-8")).items():
                if not isinstance(item,dict) or not item.get("artifact_dir"):continue
                src=Path(item["artifact_dir"])
                dst=ROOT/"platform_projects"/platform/("control_"+label)
                shutil.copytree(src,dst,dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("*.cache","*.opt","*.bak","__pycache__"))
    atomic_json(ROOT/"platform_projects"/"project_index.json",rows)
    print("Collected",len(rows),"representative projects")


if __name__=="__main__":main()
