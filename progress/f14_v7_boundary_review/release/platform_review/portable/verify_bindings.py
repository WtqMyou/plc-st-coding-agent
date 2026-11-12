"""Offline DINT binding checks. Use --release to point to an extracted F1.4."""
import argparse
import hashlib
import json
import sys
from collections import deque
from copy import deepcopy
from pathlib import Path


HERE = Path(__file__).resolve().parent
PROFILE = "public-hard-04.dint-array.st"


def score(local_tests, problem_cls, dataset, code):
    result = local_tests(code, problem_cls.from_dict(dataset))
    return {
        "local_static_and_interface_passed": result.compiles,
        "passed": result.tests_passed,
        "total": result.tests_total,
        "failures": [case.tc_id for case in result.cases if not case.passed],
    }


def directed_rows(lower, capacity):
    # The independent oracle stores items in logical FIFO order, without using ST indices.
    seed = [111 + i for i in range(capacity)]
    queue = deque()
    rows = []
    previous_en = previous_de = False
    item = -1234

    def scan(label, en=False, de=False, reset=False, value=None):
        nonlocal previous_en, previous_de, item
        if en and de:
            raise ValueError("Conflicting requests outside the course contract")
        constants = {}
        if value is not None:
            item = value
            constants["item"] = item
        status = 0
        if reset:
            queue.clear()
        elif en and not previous_en:
            if len(queue) == capacity:
                status = 0x8002
            else:
                queue.append(item)
        elif de and not previous_de:
            if not queue:
                status = 0x8001
            else:
                item = queue.popleft()
        previous_en, previous_de = en, de
        row = dict(tc_id=label, mode="sequence", group="bound",
                   inputs={"enqueue": en, "dequeue": de, "reset": reset},
                   const_inputs=constants, expected={"item": item, "status": status, "elementCount": len(queue)})
        if not rows:
            row["init"] = {"buffer": {"lower": lower, "values": seed}, "item": -1234}
        rows.append(row)

    scan("prefilled_storage_starts_empty", de=True)
    scan("idle_after_empty")
    values = [-2147483648, 2147483647, -99, 101]
    for i in range(capacity):
        scan(f"fill_{i}", en=True, value=values[i])
        scan(f"release_en_{i}")
    scan("full_reject", en=True, value=-101)
    scan("held_en_does_not_repeat", en=True, value=-102)
    scan("pop_front", de=True)
    scan("held_de_does_not_repeat", de=True)
    scan("wrap", en=True, value=708)
    for i in range(capacity):
        scan(f"drain_{i}", de=True)
        scan(f"release_de_{i}")
    scan("one_more_pop", de=True)
    scan("idle_after_reject")
    scan("refill", en=True, value=444)
    scan("reset_with_de", de=True, reset=True)
    scan("de_held_after_reset", de=True)
    scan("reset_with_en", en=True, reset=True, value=23)
    scan("en_held_after_reset", en=True)
    scan("release_after_reset")
    scan("rearmed", en=True, value=99)
    scan("rearmed_pop", de=True)
    return rows


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = args.release.resolve()
    sys.path.insert(0, str(root))
    from stbench.evaluation import check_interface, local_tests
    from stbench.schema import Problem
    from stbench.st.typecheck import check_st

    base = root / "datasets/public/public-hard-04.json"
    original_ref = base.parent / "tests/public-hard-04.reference.st"
    raw = json.loads(base.read_bytes())
    candidate_bytes = (HERE / PROFILE).read_bytes()
    code = candidate_bytes.decode("utf-8")
    if not check_st(code).ok:
        raise RuntimeError("Adapted ST failed local static checks")
    # Fail closed if a future release no longer contains the original interface.
    original = {v["name"]: v["data_type"] for v in raw["variables"]}
    assert original["item"] == original["buffer"] == "VARIANT"
    assert check_interface(code, Problem.from_dict(raw)), "Separate binding must fail the course interface check"
    bound = deepcopy(raw)
    for v in bound["variables"]:
        if v["name"] == "item":
            v["data_type"] = "DINT"
        elif v["name"] == "buffer":
            v["data_type"] = "ARRAY[*] OF DINT"
    official = score(local_tests, Problem, bound, code)
    assert official["local_static_and_interface_passed"] and official["passed"] == official["total"] == 31
    result = {
        "subject": "Separate typed DINT binding, offline STBench execution",
        "course_dataset_sha256": digest(base.read_bytes()),
        "course_reference_sha256": digest(original_ref.read_bytes()),
        "typed_reference_sha256": digest(candidate_bytes),
        "original_interface_accepts_typed_source": False,
        "official_case_replay_with_typed_interface": official,
        "directed": [],
    }
    # A pair of equal-sized buffers with different lower bounds must produce
    # the same queue outputs. All instances have nonzero initial slot contents.
    for lower, cap in [(1, 2), (-2, 2), (0, 4), (7, 4), (-5, 4)]:
        suite = {**bound, "case_mode": "sequence", "test_cases": directed_rows(lower, cap)}
        good = score(local_tests, Problem, suite, code)
        assert good["local_static_and_interface_passed"] and good["passed"] == good["total"], good
        row = {"lower": lower, "upper": lower + cap - 1, "capacity": cap, **good}
        if lower != 1:
            wrong = code.replace("LOWER_BOUND(buffer, 1) + (tail - 1)", "tail")
            bad = score(local_tests, Problem, suite, wrong)
            assert wrong != code and bad["local_static_and_interface_passed"] and bad["passed"] < bad["total"], bad
            row["incorrect_one_based_write"] = {"passed": bad["passed"], "total": bad["total"],
                                                "first_failure": bad["failures"][0]}
        result["directed"].append(row)
    result["target_evidence"] = {"native_build": "not_run_by_this_script", "native_execution": "not_run_by_this_script"}
    data = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_bytes(data.encode("utf-8"))
    else:
        print(data, end="")


if __name__ == "__main__":
    main()
