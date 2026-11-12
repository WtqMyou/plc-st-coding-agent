"""Only accept per-scan inputs permitted by the archived public task definitions."""

from itertools import product
from math import prod


def valid_route(length, sequence):
    return (type(length) is int and 1 <= length <= 8 and
            isinstance(sequence, (list, tuple)) and len(sequence) == 8 and
            sequence[length - 1] == 5 and all(2 <= station <= 4 for station in sequence[:length - 1]))


def valid_modes(manual, step, cycle, continuous):
    return sum(map(bool, (manual, step, cycle, continuous))) <= 1


def scan_contract(pid, domains):
    """Return the tuple predicate and size of the legal per-scan alphabet."""
    if pid == "public-hard-02":
        fields, check = ("processlength", "processsequence"), valid_route
    elif pid == "public-hard-05":
        fields = ("manualmode", "singlestepmode", "singlecyclemode", "continuousmode")
        check = valid_modes
    else:
        return None, None

    names = [name.lower() for name in domains]
    if any(name not in names for name in fields):
        raise ValueError("missing caller input domain for " + pid)
    indices = [names.index(name) for name in fields]
    axes = list(domains.values())
    legal = sum(check(*values) for values in product(*(axes[i] for i in indices)))
    if not legal:
        raise ValueError("empty legal caller input domain for " + pid)
    return (lambda values: check(*(values[i] for i in indices))), legal * prod(
        len(axis) for i, axis in enumerate(axes) if i not in indices)
