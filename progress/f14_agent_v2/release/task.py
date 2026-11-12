"""Export a frozen user message, or function-test an ST answer with the release judge."""
import argparse
import json
from pathlib import Path
import sys

from stbench.evaluation import local_tests
from stbench.harness.prompts import build_task_prompt
from stbench.schema import Problem

ROOT = Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    paths = {p.stem: p for p in ROOT.glob("datasets/*/*.json")}
    parser.add_argument("pid", choices=sorted(paths))
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--prompt", action="store_true", help="write the exact initial user message")
    action.add_argument("--candidate", type=Path, metavar="ANSWER.st", help="run the functional judge")
    parser.add_argument("--output", type=Path, help="save UTF-8 without newline translation")
    args = parser.parse_args()
    p = Problem.load(paths[args.pid])
    success = True
    if args.prompt:
        content = build_task_prompt(p)
    else:
        result = local_tests(args.candidate.read_text(encoding="utf-8-sig"), p)
        content = json.dumps(result.to_dict(), ensure_ascii=False, indent=2)
        success = result.compiles and result.all_tests_passed
    if args.output:
        args.output.write_bytes(content.encode("utf-8"))
    else:
        sys.stdout.buffer.write(content.encode("utf-8"))
    return 0 if success else 1

if __name__ == "__main__":
    raise SystemExit(main())
