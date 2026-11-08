"""Mirror allowlisted study evidence and push progress; never generate model requests."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[2]
ROOT = REPO / 'agent_dev_r9_stage3'
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'scripts'))
from stbench.campaign import configuration
from stbench.evaluation import atomic_json
from campaign_status import load, registered_process_alive
from r9_stage4_coverage import CONFIG, stamp, write_report

REPO = ROOT.parent
DESTINATION = Path('progress/evidence/r9_six_task_coverage_20261102')
ROOT_FILES = ('study_plan.json', 'prepared.json', 'validation.json', 'native_preflight.json', 'enum_native_controls.json',
              'snapshot_manifest.json', 'study_state.json', 'study_summary.json',
              'run_environment.json', '实验状态.md', '实验状态.html')


def assert_publishable(raw, name):
    patterns = (rb'\bsk-[A-Za-z0-9_-]{16,}', rb'\bgh[pousr]_[A-Za-z0-9]{30,}',
                rb'\bgithub_pat_[A-Za-z0-9_]{30,}',
                rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----')
    known = [os.environ.get(n, '').encode() for n in
             ('DMXAPI_API_KEY', 'OPENAI_API_KEY', 'GH_TOKEN', 'GITHUB_TOKEN')]
    if any(re.search(p, raw) for p in patterns) or any(k in raw for k in known if len(k) > 12):
        raise RuntimeError('Credential-like content blocked from Git: ' + name)


def publish_files(root, destination=DESTINATION):
    root = Path(root)
    source = [root / name for name in ROOT_FILES if (root / name).is_file()]
    source += sorted((root / 'jobs').glob('*/*.json'))
    source += sorted((root / 'reused').glob('*/*.json'))
    copied = []
    for path in source:
        raw = path.read_bytes()
        if path.suffix == '.json':
            json.loads(raw)  # Never publish a partially written record.
        relative = path.relative_to(root)
        assert_publishable(raw, relative.as_posix())
        out = REPO / destination / relative
        out.parent.mkdir(parents=True, exist_ok=True)
        if not out.exists() or out.read_bytes() != raw:
            out.write_bytes(raw)
        copied.append(dict(path=relative.as_posix(), bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest()))
    manifest = json.dumps(dict(source_root=str(root), files=copied,
                          excluded=['credentials', 'raw budget ledger', 'process markers', 'native project binaries']),
                          ensure_ascii=False, indent=2).encode('utf-8') + b'\n'
    out = REPO / destination / 'publication_manifest.json'
    if not out.exists() or out.read_bytes() != manifest:
        out.write_bytes(manifest)
    return len(copied)


def run_git(args):
    env = dict(os.environ, GCM_INTERACTIVE='never', GIT_TERMINAL_PROMPT='0')
    result = subprocess.run(['git'] + args, cwd=REPO, capture_output=True, text=True,
                            encoding='utf-8', errors='replace', env=env, timeout=60)
    if result.returncode:
        # Git uses the credential manager; credentials are never placed in command arguments.
        raise RuntimeError('Git command failed: ' + args[0] + '; ' + result.stderr.strip()[:600])
    return result.stdout.strip()


def sync_git(summary, expected_head):
    if run_git(['branch', '--show-current']) != 'main':
        raise RuntimeError('Automatic progress sync requires main; user branch left untouched')
    if run_git(['remote', 'get-url', 'origin']) != 'https://github.com/WtqMyou/plc-st-coding-agent.git':
        raise RuntimeError('Automatic progress sync remote changed')
    head = run_git(['rev-parse', 'HEAD'])
    if expected_head and head != expected_head:
        raise RuntimeError('Repository changed outside this monitor; automatic commits paused')
    staged = run_git(['diff', '--cached', '--name-only']).splitlines()
    if any(not name.startswith(DESTINATION.as_posix() + '/') for name in staged):
        raise RuntimeError('Other staged work exists; automatic commits paused')
    path = DESTINATION.as_posix()
    if run_git(['status', '--porcelain', '--', path]):
        run_git(['add', '--', path])
        run_git(['commit', '--quiet', '--only', '-m',
                 f"data: six-task coverage {summary.get('recorded', 0)}/24 {summary.get('state', 'prepared')}", '--', path])
        head = run_git(['rev-parse', 'HEAD'])
    # Also retry publishing an already-created progress commit after a network failure.
    run_git(['push', 'origin', 'main'])
    if run_git(['ls-remote', 'origin', 'refs/heads/main']).split()[0] != head:
        raise RuntimeError('Remote progress revision does not match the local commit')
    return head


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--once', action='store_true')
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    cfg = configuration(str(CONFIG))
    root = Path(cfg['campaign_root'])
    expected_head = run_git(['rev-parse', 'HEAD']) if args.publish else None
    last_published_signature = None
    while True:
        state = load(root / 'study_state.json')
        marker = load(root / 'active_run.json')
        alive = registered_process_alive(marker)
        if state.get('state') == 'running' and marker and not alive:
            atomic_json(root / 'study_state.json', dict(state='stopped', at=stamp(),
                error='Runner disappeared; preserve all reservations and inspect before any restart'))
            write_report(cfg, load(root / 'study_plan.json'))
            state = load(root / 'study_state.json')
        terminal = state.get('state') in ('completed', 'stopped') and not alive
        if terminal:
            write_report(cfg, load(root / 'study_plan.json'))
        try:
            count = publish_files(root)
            summary = load(root / 'study_summary.json')
            signature = hashlib.sha256((REPO / DESTINATION / 'publication_manifest.json').read_bytes()).hexdigest()
            if args.publish and signature != last_published_signature:
                # Remember a created commit even if its network push subsequently fails.
                try:
                    expected_head = sync_git(summary, expected_head)
                    last_published_signature = signature
                except Exception:
                    current = run_git(['rev-parse', 'HEAD'])
                    if current != expected_head and run_git(['log', '-1', '--format=%s']).startswith('data: six-task coverage '):
                        expected_head = current
                    raise
            atomic_json(root / 'git_sync_status.json', dict(state='synced' if args.publish else 'copied',
                        commit=expected_head, copied_files=count, at=stamp(), remote='origin/main'))
        except Exception as error:
            atomic_json(root / 'git_sync_status.json', dict(state='needs_attention', error=str(error), at=stamp()))
            if terminal or args.once:
                raise
        if args.once or terminal:
            return
        time.sleep(15)


if __name__ == '__main__':
    main()
