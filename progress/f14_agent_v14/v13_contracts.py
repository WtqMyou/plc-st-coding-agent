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


def clause_index(user):
    """Locate verbatim clauses in the unchanged user message without copying them twice."""
    rows=[];cursor=0
    for clause in clauses(user):
        start=user.find(clause['text'],cursor)
        assert start>=0,'Every citation must refer to an actual original clause'
        end=start+len(clause['text']);cursor=end
        rows.append(dict(id=clause['id'],start_character=start,end_character_exclusive=end))
    return rows


def prompt_extension(user):
    return (DESIGN_INSTRUCTION + '\n' + CAPABILITIES +
            '\nVerbatim public requirement clauses (for design citations only):\n' +
            json.dumps(clauses(user), ensure_ascii=False))


def relevant_clauses(user, variables, names, maximum=4):
    stop={'control','output','operation','indicator','signal','the','for','used','value','input'}
    words = {word.lower() for name in names for word in re.findall(r'[A-Z]?[a-z]+|[A-Z]+(?![a-z])',name) if len(word)>2 and word.lower() not in stop}
    for variable in variables:
        if variable.name.lower() in {n.lower() for n in names}:
            words.update(w for w in re.findall(r'[a-zA-Z]{4,}', variable.description.lower()) if w not in stop)
    ranked = sorted(enumerate(clauses(user)),
                    key=lambda item: (-sum(word in item[1]['text'].lower() for word in words), item[0]))
    return [clause for _, clause in ranked[:maximum]]


def compliance(source):
    match = re.search(r'\(\*\s*ENGINEERING_CONTRACT\b(.*?)\*\)', source, re.I | re.S)
    return dict(present=bool(match), comment_lines=len(match.group(0).splitlines()) if match else 0,
                cited_public_clauses=sorted(set(re.findall(r'PUB\d{3}', match.group(0)))) if match else [])


DESIGN_INSTRUCTION += " Also emit a separate ST comment (* CONTRACT_RULES [...] *) containing a JSON list for any unconditional public Boolean output latch explicitly required by the task. Each supported rule has kind=hold_until_reset, output=<public BOOL output>, set_input=<public BOOL input>, reset_input=<public BOOL input or null>. Use [] when no such unconditional latch is specified. The checker executes these declarations on generated public-input traces; do not declare conditions the implementation does not satisfy. These checks supplement the task and do not change its scoring."
CAPABILITIES += " CODESYS STRING scalar indexing is zero-based and returns BYTE, not a one-character STRING. For ASCII text, iterate byte indices 0 through LEN(text)-1, or use MID(text,1,position) with one-based position to get a one-character STRING. Do not mix those indexing conventions. Whole STRUCT and ARRAY assignments copy values. Generic TO_LREAL accepts numeric/BOOL operands; TO_REAL rounds to IEEE binary32. R_TRIG/F_TRIG and TON keep state across calls. On same-scan state changes determine the final timer enable before calling the timer so a newly enabled output and its elapsed-time origin agree. When multiple command inputs are asserted, preserve the public operation contracts or explicitly report an unsupported combination through an existing error interface; do not silently drop commands through an arbitrary priority."

CAPABILITIES += " Prefix helper local names with tmp_ or local_ to avoid collisions with standard functions and reserved words, including LEN, S and R. Never shadow a standard function that the block calls."

CAPABILITIES += " RETURN terminates the entire current function-block invocation, including when nested in IF, CASE or a loop; it does not clear retained state. EXIT terminates only the innermost loop. Standard TON.Q uses elapsed >= PT and TON.ET saturates at PT. Determine whether a threshold is strict from its public wording; apply the supplied arithmetic only to the quoted condition and its stated time resolution. Do not add a scan of delay by reading a stale timer Q. For every task independently audit: reset/stop priority, state retention, first invocation versus later invocations, rising-edge memory, array lower bounds and ordinal positions, stored identifier versus slot, numeric width, and simultaneous operations as explicitly specified. A sequence counterexample contains its complete public prefix; replay it from the stated initialization, preserving state between scans. Fix the cause while retaining already correct paths. No task ID, reference program or private assertion is a design rule."
