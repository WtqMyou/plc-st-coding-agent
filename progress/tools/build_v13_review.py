"""Import the reviewed dataset without writing any historical source or archive."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import sys
import tempfile
import zipfile

REPO = Path(__file__).resolve().parents[2]
ROOT = REPO / 'progress/v13'
sys.path.insert(0, str(ROOT))


def dump(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--import-upstream', action='store_true')
    ap.add_argument('--write', action='store_true')
    args = ap.parse_args()
    if args.import_upstream:
        path = REPO / '11.8 复核记录+意见/stbench_v1.3_20261028_完整工程.zip'
        assert hashlib.sha256(path.read_bytes()).hexdigest() == '6464cc7f9315fdcad17c41311f0290899122c0b6c0c31394cbf6f2827a25cbcc'
        entries = {}
        with zipfile.ZipFile(path) as z:
            base = next(n[:-len('stbench/schema.py')] for n in z.namelist() if n.endswith('/stbench/schema.py'))
            names = [n for n in z.namelist() if n.startswith(base+'datasets/') and n.endswith('.json') and n[len(base):].count('/') == 2 and Path(n).name.startswith(('public-', 'self-'))]
            names.append(base+'datasets/selfmade_new5.py')
            for n in names:
                relative = n[len(base+'datasets/'):]
                data = z.read(n)
                target = ROOT / 'upstream' / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                with target.open('xb') as f:
                    f.write(data)
                entries[relative] = hashlib.sha256(data).hexdigest()
        with (ROOT/'upstream_manifest.json').open('xb') as f:
            f.write(dump(dict(zip_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), files=entries)))
    from revision import definitions, VERSION
    expected = {}
    tasks = definitions()
    for d in tasks:
        relative = f'{d["source"]}/{d["pid"]}.json'
        expected[relative] = (ROOT/'upstream'/relative).read_bytes() if d['source'] == 'public' else dump(d)
    assert len(expected) == 35
    for source in ('public', 'selfmade'):
        expected[source+'/_index.json'] = dump([dict(pid=d['pid'], title=d['title'], difficulty=d['difficulty'],
            n_vars=len(d['variables']), n_specs=len(d['specs']), n_ltl=sum(bool(s['ltl']) for s in d['specs']),
            n_cases=len(d['test_cases']), case_mode=d.get('case_mode', 'single'))
            for d in tasks if d['source'] == source])
    # Build all files successfully in a temporary directory before touching output.
    with tempfile.TemporaryDirectory(prefix='plc_v13_build_') as directory:
        for relative, data in expected.items():
            p = Path(directory)/relative
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
        for relative, data in expected.items():
            p = ROOT/'datasets'/relative
            if args.write:
                p.parent.mkdir(parents=True, exist_ok=True)
                with p.open('wb') as f:
                    f.write(data)
            elif not p.is_file() or p.read_bytes() != data:
                raise ValueError('Rebuild drift: '+relative)
        actual = {p.relative_to(ROOT/'datasets').as_posix() for p in (ROOT/'datasets').glob('*/*.json')}
        assert actual == set(expected), 'Unexpected dataset file set'
    print(json.dumps(dict(version=VERSION, problems=len(tasks), cases=sum(len(d['test_cases']) for d in tasks), mode='generate' if args.write else 'check')))


if __name__ == '__main__':
    main()
