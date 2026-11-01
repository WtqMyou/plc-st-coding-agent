"""Record local executable identities; never read or print credential values."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from stbench.campaign import configuration, digest
from stbench.cli import doctor
from stbench.evaluation import atomic_json
from stbench.platforms import CodesysBackend, OpenPLCBackend


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', type=Path, required=True)
    args = ap.parse_args()
    if args.out.exists():
        raise RuntimeError('Use a new environment evidence file')
    cfg = configuration('')
    codex = shutil.which('codex')
    version = subprocess.run([codex, '--version'], capture_output=True, text=True, timeout=15, check=True).stdout.strip()
    result = dict(recorded_utc=datetime.now(timezone.utc).isoformat(), source_sha256=digest(),
                  doctor=doctor(cfg), codex=dict(executable=codex, version=version,
                  sha256=hashlib.sha256(Path(codex).read_bytes()).hexdigest()),
                  platforms={p.name: p.identity() for p in (CodesysBackend(cfg), OpenPLCBackend(cfg))},
                  models=[{k: s[k] for k in ('id', 'model', 'base_url', 'generation_protocol', 'parameters')}
                          for s in cfg['models']], limits=cfg['limits'], profile='portable-frame-v4',
                  note='Installed executable identities and configured limits; actual compilation is evidenced separately')
    atomic_json(args.out, result)
    print(json.dumps(dict(out=str(args.out.resolve()), codex_version=version, source_sha256=digest())))


if __name__ == '__main__':
    main()
