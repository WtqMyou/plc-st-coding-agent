"""Positive and deliberately invalid candidates through the actual native compiler."""
import argparse
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.cli import config
from stbench.schema import Problem
from stbench.platforms import CodesysBackend,OpenPLCBackend
from stbench.evaluation import atomic_json


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--platform",choices=["codesys","openplc","both"],default="both")
    args=ap.parse_args()
    cfg=config("")
    p=Problem.from_dict(dict(pid="compiler-control",source="selfmade",difficulty="easy",
        title="Compiler controls",requirements="b equals a",
        variables=[dict(name="a",data_type="BOOL",direction="input"),
                   dict(name="b",data_type="BOOL",direction="output")]))
    source="FUNCTION_BLOCK FB\nVAR_INPUT a:BOOL; END_VAR\nVAR_OUTPUT b:BOOL; END_VAR\nb:=a;\nEND_FUNCTION_BLOCK"
    rows={}
    for cls in (CodesysBackend,OpenPLCBackend):
        b=cls(cfg)
        if args.platform not in ("both",b.name):continue
        positive=b.compile(source,p)
        negative=b.compile(source.replace("b:=a;","b:=;"),p)
        rows[b.name]={"positive":positive.to_dict(),"negative":negative.to_dict(),
                      "passed":positive.status=="passed" and negative.status=="failed"}
        atomic_json(ROOT/"evidence"/(b.name+"_compiler_controls.json"),rows[b.name])
        print(b.name,positive.status,negative.status,flush=True)
    return int(not all(r["passed"] for r in rows.values()))


if __name__=="__main__":raise SystemExit(main())
