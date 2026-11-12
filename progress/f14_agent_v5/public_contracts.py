"""Engineering design aids derived exclusively from the original public task."""
import json
import re

PIDS = ('public-easy-01', 'public-easy-04', 'public-hard-03',
        'public-medium-03', 'public-medium-04', 'public-medium-08')

DESIGN_INSTRUCTION = '''Before implementing, put a concise ENGINEERING_CONTRACT comment inside the ST block (up to 12 lines). For each output or state group state: activation, retention/hold, explicit reset/deactivation, same-scan priority, and units/boundaries. Cite PUB clause IDs where relevant. This is a reviewable design table, not a reasoning transcript. Use only the task's public requirements. Preserve output state when the task explicitly requires retention; do not assume a mutually exclusive state machine automatically shuts down earlier outputs. Do not invent resets, interlocks, edge triggers or operation priorities. Mark unspecified details as unspecified and implement a consistent interpretation. Check strict > versus >=, boundary scan timing, TIME milliseconds versus LTIME nanoseconds, zero/reset behavior, array slot versus stored identifier and simultaneous operations when applicable. Return the table as an ST comment followed by the complete implementation in the same single fenced ST block. Missing table is recorded as process compliance, not a functional scoring failure.'''

CAPABILITIES = '''Target tools: CODESYS 3.5 native compilation; deterministic local scan interpreter; bounded LTL checking after functional success. Supported core: IF/ELSIF, nested CASE, FOR/WHILE/REPEAT, named or anonymous integer enums, declared STRUCT/ARRAY, TIME/LTIME, TON, R_TRIG/F_TRIG, bit selectors, SHL/SHR, explicit IEC conversions and exact generic TO_BOOL/integer/bit conversions. Prefer explicit source_TO_target conversions, especially for REAL. Declare helper types and functions before use; avoid external library helpers unless supplied by the task. Keep every original public interface type and field spelling. Tool limits never authorize changing the task interface. Do not replace LTIME with floating-point arithmetic or VARIANT with DINT.'''


def clauses(user):
    """Number verbatim requirement lines; do not read judge expectations/specs."""
    match = re.search(r'(?ms)^## Requirements\s*\n(.*?)(?=^## |\Z)', user)
    body = match.group(1) if match else user
    return [dict(id=f'PUB{i:03}', text=line.strip())
            for i, line in enumerate((line for line in body.splitlines() if line.strip()), 1)]


def prompt_extension(user):
    return (DESIGN_INSTRUCTION + '\n' + CAPABILITIES +
            '\nVerbatim public requirement clauses (for design citations only):\n' +
            json.dumps(clauses(user), ensure_ascii=False))


def relevant_clauses(user, variables, names, maximum=4):
    words = {name.lower() for name in names}
    for variable in variables:
        if variable.name.lower() in words:
            words.update(re.findall(r'[a-zA-Z]{4,}', variable.description.lower()))
    ranked = sorted(enumerate(clauses(user)),
                    key=lambda item: (-sum(word in item[1]['text'].lower() for word in words), item[0]))
    return [clause for _, clause in ranked[:maximum]]


def compliance(source):
    match = re.search(r'\(\*\s*ENGINEERING_CONTRACT\b(.*?)\*\)', source, re.I | re.S)
    return dict(present=bool(match), comment_lines=len(match.group(0).splitlines()) if match else 0,
                cited_public_clauses=sorted(set(re.findall(r'PUB\d{3}', match.group(0)))) if match else [])
