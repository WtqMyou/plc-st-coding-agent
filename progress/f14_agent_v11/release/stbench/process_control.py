"""Bound CLI wall time without waiting for pipes inherited by descendants."""
import os
from pathlib import Path
import signal
import subprocess
import time


def stop_tree(process):
    if process.poll() is not None:
        return
    if os.name == 'nt':
        try:
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=2, creationflags=subprocess.CREATE_NO_WINDOW)
        except (OSError, subprocess.TimeoutExpired):
            pass
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if process.poll() is None:
        process.kill()
    try:
        process.wait(timeout=.5)
    except subprocess.TimeoutExpired:
        pass


def run_logged(args, *, work, input_text, env, timeout, failure=None):
    """Keep stdout/stderr on disk even on failure; stdin contains only the task prompt."""
    work = Path(work)
    prompt = work / 'prompt.txt'
    prompt.write_text(input_text, encoding='utf-8')
    options = dict(creationflags=subprocess.CREATE_NO_WINDOW) if os.name == 'nt' else dict(start_new_session=True)
    deadline = time.monotonic() + max(.01, timeout)
    with prompt.open('rb') as stdin, (work/'events.jsonl').open('xb') as stdout, (work/'stderr.log').open('xb') as stderr:
        process = subprocess.Popen(args, stdin=stdin, stdout=stdout, stderr=stderr, env=env, **options)
        try:
            while True:
                error = failure() if failure else None
                if error is not None:
                    stop_tree(process)
                    return process.returncode, False, error
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    stop_tree(process)
                    return process.returncode, True, None
                try:
                    return process.wait(timeout=min(.05, remaining)), False, None
                except subprocess.TimeoutExpired:
                    pass
        finally:
            if process.poll() is None:
                stop_tree(process)
