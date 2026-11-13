"""Replayable, model-authored exact edits. No semantic completion by the host."""
import hashlib
import json
import re

REPAIR_MODE = '''REPAIR OUTPUT MODE overrides the normal fenced-ST output instruction for this request.
Return one JSON object: {"edits":[{"old":"exact unique substring in the supplied candidate","new":"replacement"}]}.
Choose the smallest semantic fix and preserve already working paths. Each old string must occur exactly once; include enough surrounding lines to disambiguate. Changes are applied sequentially.
If the implementation depends on unavailable pointer/library machinery or needs a different architecture, use {"replace_program":"complete self-contained ST program"} instead.
The host applies only your exact edits, then independently compiles and tests the resulting full program. Do not include assertion expectations, task answers from elsewhere, or prose outside JSON.'''

def apply(text, base):
    raw=text.strip()
    if raw.startswith('```'):
        raw=re.sub(r'^```[^\n]*\n','',raw);raw=re.sub(r'\n```\s*$','',raw)
    data=json.loads(raw)
    if set(data)=={'replace_program'}:
        source=data['replace_program']
        if not isinstance(source,str) or not source.strip():raise ValueError('Empty replacement program')
        return source,dict(mode='model_replacement',base_sha256=hashlib.sha256(base.encode()).hexdigest(),plan=data)
    if set(data)!={'edits'} or not isinstance(data['edits'],list) or not 1<=len(data['edits'])<=24:raise ValueError('Invalid exact-edit schema')
    source=base
    for edit in data['edits']:
        if set(edit)!={'old','new'} or not all(isinstance(v,str) for v in edit.values()):raise ValueError('Invalid edit fields')
        if not edit['old'] or source.count(edit['old'])!=1:raise ValueError('Edit anchor must occur exactly once')
        source=source.replace(edit['old'],edit['new'],1)
    if source==base:raise ValueError('Edit plan leaves candidate unchanged')
    return source,dict(mode='model_exact_edits',base_sha256=hashlib.sha256(base.encode()).hexdigest(),plan=data)

PUBLIC_EXECUTION_CONTRACT = '''Published execution-contract supplement V12, shared across every task in this version:
1. Commands for opposite movements of the same physical axis must never be energized together. Unless the public task states a priority, inhibit both directions when both commands conflict. This physical-direction rule is separate from mutually exclusive operating modes. It clarifies the assessment convention for contradictory direction inputs; it does not authorize arbitrary priorities or interlocks between independent outputs.
2. For sequential processes, a step transition and an output's lifetime are separate. When the public task says an output continues working and names later start events without a stop event, retain that output until the stated cycle reset/stop. Do not infer a stop merely from another actuator starting. Pulse and combinational outputs still follow their stated contracts.
3. For repeated timed cycles, derive timer enable from the final same-scan state, not a stale pre-transition state. A timer must have a false/reset call between intervals that require independent timing. Audit the first scan of re-enabled output, threshold scan, cooldown-completion scan, and a second entire interval. Do not introduce an additional scan or reuse a completed timer's Q.
4. Managed VARIANT functional-tool ABI: a VARIANT IN_OUT is a transparent caller-bound mutable reference. A bound one-dimensional array supports LOWER_BOUND(buffer,1), UPPER_BOUND(buffer,1), ordinary buffer[index] reads/writes, and scalar assignment to/from a bound VARIANT item of the matching element type. Caller bounds and element types are preserved. This ABI supplies reference semantics; no __VARINFO, __SYSTEM.VAR_INFO, raw pointer dereference, ADR, MEMCPY or external libraries are needed. Keep the original VARIANT declarations. The native CODESYS profile does not support this original interface and its native result remains separate. This capability statement supplies no queue algorithm or reference solution.'''
