"""Run the validated campaign; keep durable completion state across chat restarts."""
from datetime import datetime, timezone
import argparse
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from stbench.campaign import configuration, credentials, digest, main
from stbench.evaluation import atomic_json

ap = argparse.ArgumentParser()
ap.add_argument('--validation', type=Path, required=True)
args = ap.parse_args()
cfg = configuration('')
out = Path(cfg['campaign_root'])
proof = json.loads(args.validation.read_text(encoding='utf-8'))
if proof.get('passed') is not True or proof.get('source_sha256') != digest():
    raise RuntimeError('Frozen source validation mismatch')
archive = out / 'frozen_source_before_campaign.zip'
with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as z:
    for folder in ('stbench', 'datasets', 'scripts'):
        for p in sorted((ROOT / folder).rglob('*')):
            if p.is_file() and '__pycache__' not in p.parts:
                z.write(p, p.relative_to(ROOT).as_posix())
    z.write(ROOT / 'config.dmxapi.json', 'config.dmxapi.json')
credentials(cfg)
awake = False
if sys.platform == 'win32':
    import ctypes
    awake = bool(ctypes.windll.kernel32.SetThreadExecutionState(0x80000001))
atomic_json(out / 'execution_state.json', dict(system_awake_requested=awake, display_awake_requested=False))
try:
    result = main(['all', '--live'])
except BaseException as error:
    atomic_json(out / 'runner_exit.json', dict(state='stopped', error_type=type(error).__name__,
        error=str(error), at=datetime.now(timezone.utc).isoformat(), source_sha256=digest()))
    raise
else:
    atomic_json(out / 'runner_exit.json', dict(state='completed', returncode=result,
        at=datetime.now(timezone.utc).isoformat(), source_sha256=digest()))
finally:
    if awake:
        ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
