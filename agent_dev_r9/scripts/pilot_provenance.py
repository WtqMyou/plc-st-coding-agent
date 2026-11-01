"""Validate compatible one-candidate pilot provenance, including earlier reuse links."""
import hashlib
import json
from pathlib import Path

ALLOWED = {'stbench/campaign.py', 'stbench/harness/engine.py'}


def accepted_sources(freeze, proof=None, *, root=None, depth=0):
    if depth > 8:
        raise RuntimeError('Pilot provenance chain is too deep')
    result = {freeze['judge_sha256']}
    if proof is None:
        return result
    old = proof['source_freeze']
    changed = {k for k in set(old['files']) | set(freeze['files'])
               if old['files'].get(k) != freeze['files'].get(k)}
    if (not changed <= ALLOWED or sorted(changed) != sorted(proof['changed_files']) or
            any(old.get(k) != freeze.get(k) for k in ('version', 'config', 'profile', 'routes', 'tasks')) or
            proof['current_source_sha256'] != freeze['judge_sha256']):
        raise RuntimeError('Incompatible pilot provenance')
    if root is not None:
        root = Path(root).resolve()
        for item in proof['copied_files']:
            relative = Path(item['path'])
            target = (root / relative).resolve()
            if (relative.is_absolute() or root not in target.parents or
                    not relative.parts or relative.parts[0] != 'pilot' or
                    hashlib.sha256(target.read_bytes()).hexdigest() != item['sha256']):
                raise RuntimeError('Pilot copied-file evidence mismatch')
    result.update(accepted_sources(old, proof.get('previous_reuse'), root=root, depth=depth + 1))
    return result


def load_sources(root, freeze):
    path = Path(root) / 'pilot_reuse.json'
    proof = json.loads(path.read_text(encoding='utf-8')) if path.exists() else None
    return accepted_sources(freeze, proof, root=root)
