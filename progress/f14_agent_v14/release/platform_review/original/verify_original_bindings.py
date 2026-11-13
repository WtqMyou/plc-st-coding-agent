"""Check concrete caller examples against the original public-hard-04 ST in the delivered project."""
import argparse
from collections import deque
from hashlib import sha256
import json
from pathlib import Path
import sys


def require(value, message):
    if not value:
        raise AssertionError(message)


def check_binding(parsed, element, lower, capacity, values):
    from stbench.st.interp import ArrayValue, Interpreter, VariantValue

    upper = lower + capacity - 1
    array_tag = f"ARRAY[{lower}..{upper}] OF {element}"
    scalar_type = {"DINT": int, "BOOL": bool, "REAL": float, "STRING": str}[element]
    require(len(values) > capacity and all(type(v) is scalar_type for v in values), array_tag)
    fill = scalar_type()
    storage = ArrayValue(lower, upper, [fill] * capacity)
    machine = Interpreter(parsed.pou, parsed.structs)
    machine.set_var("buffer", VariantValue(storage, array_tag))
    machine.set_var("item", VariantValue(fill, element))
    queue = deque()
    scans = []
    returned = []
    unchanged = object()

    def step(op, supplied=unchanged):
        if supplied is not unchanged:
            machine.set_var("item", VariantValue(supplied, element))
        prev_item = machine.get_var("item").value
        prev_buffer = list(storage.items)
        inputs = {"enqueue": op in ("enqueue", "reset-enqueue"), "dequeue": op == "dequeue",
                  "reset": op == "reset-enqueue"}
        for name, value in inputs.items():
            machine.set_var(name, value)
        expected_status = 0
        expected_item = prev_item
        if inputs["reset"]:
            queue.clear()
        elif op == "enqueue":
            if len(queue) == capacity:
                expected_status = 0x8002
            else:
                queue.append(prev_item)
        elif op == "dequeue":
            if queue:
                expected_item = queue.popleft()
            else:
                expected_status = 0x8001
        machine.scan()
        actual_item = machine.get_var("item")
        actual_buffer = machine.get_var("buffer")
        actual = {"status": machine.get_var("status"), "elementCount": machine.get_var("elementCount"),
                  "item": actual_item.value}
        expected = {"status": expected_status, "elementCount": len(queue), "item": expected_item}
        prefix = f"{array_tag}, scan {len(scans) + 1}, {op}"
        require(actual_item.tag == element and type(actual_item.value) is scalar_type, prefix + ": scalar type")
        require(actual_buffer.tag == array_tag and actual_buffer.value is storage, prefix + ": caller storage")
        require((storage.lo, storage.hi) == (lower, upper), prefix + ": bounds")
        require(all(type(v) is scalar_type for v in storage.items), prefix + ": stored payload types")
        require(actual == expected, f"{prefix}: expected {expected}, actual {actual}")
        if expected_status:
            require(prev_buffer == storage.items, prefix + ": storage changed on rejection")
        if op == "dequeue" and not expected_status:
            returned.append(actual_item.value)
        if supplied is not unchanged:
            inputs["item"] = supplied
        scans.append({"scan": len(scans) + 1, "inputs": inputs, "expected": expected,
                      "actual": actual, "storage_after": list(storage.items)})

    def pulse(op, supplied=unchanged):
        step("idle")
        step(op, supplied)

    step("dequeue", values[-1])
    step("idle")
    for value in values[:capacity]:
        pulse("enqueue", value)
    pulse("enqueue", values[-1])
    pulse("dequeue")
    pulse("enqueue", values[capacity])  # reuse the first storage slot
    for _ in range(capacity):
        pulse("dequeue")
    pulse("dequeue")
    step("idle")
    pulse("enqueue", values[0])
    pulse("reset-enqueue", values[-1])  # reset takes precedence on this enqueue edge
    pulse("dequeue")
    step("idle")
    require(returned == values[:capacity + 1], array_tag + ": FIFO order")
    return {"element_type_tag": element, "python_payload_type": scalar_type.__name__,
            "array_type_tag": array_tag, "lower": lower, "upper": upper, "capacity": capacity,
            "popped": returned, "scan_count": len(scans), "scans": scans}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2],
                        help="extracted project root containing datasets and stbench")
    parser.add_argument("--output", type=Path, help="write JSON instead of printing it")
    args = parser.parse_args()
    root = args.root.resolve()
    sys.path.insert(0, str(root))
    from stbench.st.typecheck import check_st

    rel = "datasets/public/tests/public-hard-04.reference.st"
    source = (root / rel).read_bytes()
    checked = check_st(source.decode("utf-8"))
    require(checked.ok and checked.pou is not None, "reference ST did not pass the offline checker")
    ports = {d.name.lower(): (d.section, d.data_type) for d in checked.pou.decls}
    require(all(ports[n] == ("VAR_IN_OUT", "VARIANT") for n in ("item", "buffer")), "wrong FIFO interface")
    dint = [-(2**31), 2147483647, -19, 8, 123456789]
    tests = [("DINT", lower, capacity, dint) for capacity in (2, 4) for lower in (-3, 5)]
    tests.extend([("BOOL", 0, 2, [True, False, True]),
                  ("REAL", -7, 2, [-1.25, 2.75, 0.5]),
                  ("STRING", 9, 2, ["letter A", "other", "wrap"])])
    rows = [check_binding(checked, *case) for case in tests]
    report = {"pid": "public-hard-04", "source": rel, "source_sha256": sha256(source).hexdigest(),
              "engine": "STBench local interpreter", "counted_in_946": False,
              "binding_method": "Explicit VariantValue tags on a concrete in-memory ArrayValue and scalar; samples use conforming Python values. The interpreter does not provide native IEC static type or reference ABI validation.",
              "scope": "These seven concrete caller examples and their scan schedules only.",
              "bindings_passed": len(rows), "scans_passed": sum(row["scan_count"] for row in rows), "rows": rows}
    data = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_bytes(data.encode("utf-8"))
    else:
        print(data, end="")


if __name__ == "__main__":
    main()
