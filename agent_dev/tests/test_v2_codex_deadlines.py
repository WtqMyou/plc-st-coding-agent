"""Exercise actual child processes and the installed CLI, without paid requests."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from stbench.billing import CampaignBudget
from stbench.codex_baseline import CodexProvider, ResponsesGateway
from stbench.process_control import run_logged
from stbench.providers.base import ProviderError
from stbench.transport import MeteredProvider, RequestDeadline

ROOT=Path(__file__).resolve().parents[1]


class CodexDeadlines(unittest.TestCase):
    def test_cli_tree_deadline_keeps_logs_without_inherited_pipe_wait(self):
        with tempfile.TemporaryDirectory() as d:
            work=Path(d)
            # The grandchild inherits both output handles, the original failure trigger.
            child='import time; time.sleep(30)'
            code='import subprocess,sys,time; p=subprocess.Popen([sys.executable,"-c",'+repr(child)+']); print(p.pid,flush=True); time.sleep(30)'
            start=time.monotonic()
            _,timeout,error=run_logged([sys.executable,'-c',code],work=work,input_text='',env=dict(os.environ),timeout=.5)
            self.assertTrue(timeout);self.assertIsNone(error)
            self.assertLess(time.monotonic()-start,3.5)
            pid=int((work/'events.jsonl').read_text().strip())
            if os.name=='nt':
                import ctypes
                kernel=ctypes.WinDLL('kernel32',use_last_error=True)
                kernel.OpenProcess.restype=ctypes.c_void_p
                handle=kernel.OpenProcess(0x1000,False,pid)
                if handle:
                    status=ctypes.c_ulong()
                    kernel.GetExitCodeProcess(ctypes.c_void_p(handle),ctypes.byref(status))
                    kernel.CloseHandle(ctypes.c_void_p(handle))
                    self.assertNotEqual(status.value,259,'Descendant remained alive after CLI deadline')
            self.assertTrue((work/'stderr.log').exists())

    @unittest.skipUnless(shutil.which('codex'),'Actual CLI is unavailable')
    def test_upstream_failure_aborts_actual_cli_without_a_second_request(self):
        with tempfile.TemporaryDirectory() as d:
            budget=CampaignBudget(Path(d)/'ledger.json','preflight');sent=[];failed=[]
            def sender(*args):
                sent.append(1);time.sleep(.3)
                failed.append(time.monotonic())
                raise RequestDeadline('Upstream wall deadline exceeded; no automatic retry')
            transport=MeteredProvider(dict(model='offline-timeout',base_url='https://example.invalid/v1',
                api_key_env='UNUSED',input_cny_per_million=1,output_cny_per_million=2),
                budget,offline=True,sender=sender,timeout=2)
            start=time.monotonic()
            with ResponsesGateway(provider=transport,model='offline-timeout') as gateway:
                cli=CodexProvider(gateway,model='offline-timeout',mock=True,work_root=Path(d)/'cli',timeout=12)
                with self.assertRaisesRegex(RequestDeadline,'wall deadline'):
                    cli.generate([dict(role='user',content='Return one word.')])
            # CLI startup varies under load; cancellation is measured from the actual failure.
            self.assertLess(time.monotonic()-failed[0],4.5)
            self.assertLess(time.monotonic()-start,15.5)
            self.assertEqual(len(sent),1)
            self.assertEqual(len(budget.read(allow_halted=True)['events']),1)
            logs=list((Path(d)/'cli').glob('*/events.jsonl'))
            self.assertEqual(len(logs),1)

    def test_cli_recovery_preserves_unknown_charge_and_rejects_stale_or_new_failures(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'ledger.json','preflight')
            b.reserve(.2,request=dict(model='model',timeout_seconds=420,protocol='chat'))
            original=b.snapshot();event=original['events'][0]
            b.halt('Unconfirmed upstream result; reservation retained',details=dict(
                category='request_timeout',model='model',event_index=0))
            record=dict(model='model',provider='codex-cli',experiment_kind='live',stop_reason='provider_error',
                error='Codex CLI timeout',started_at=event['created_at']-1,finished_at=event['created_at']+764,
                attempts=[dict(provider_error='Codex CLI timeout',code='',prompt_tokens=0,completion_tokens=0)])
            failure=Path(d)/'failure.json';failure.write_text(json.dumps(record))
            proof=dict(passed=True,source_sha256='old',request_seconds=420,cli_seconds=450,
                deadline_checks=dict(cli_tree_deadline=True,upstream_failure_aborts_cli=True,single_upstream_request=True))
            validation=Path(d)/'validation.json';validation.write_text(json.dumps(proof))
            with self.assertRaisesRegex(ProviderError,'current passing'):
                b.recover_codex_timeout(failure,validation)
            proof['source_sha256']=hashlib.sha256(b''.join(p.read_bytes() for p in sorted((ROOT/'stbench').rglob('*.py')))).hexdigest()
            validation.write_text(json.dumps(proof))
            recovery=b.recover_codex_timeout(failure,validation)
            self.assertEqual(b.snapshot()['events'],original['events'])
            self.assertEqual(b.snapshot()['spent_cny'],.2)
            self.assertTrue(Path(recovery['backup']).is_file())
            # Even overlapping wall-clock ranges cannot associate this record with a new event.
            b.reserve(.1,request=dict(model='model',timeout_seconds=420,protocol='chat'))
            b.halt('Unconfirmed upstream result; reservation retained',details=dict(
                category='request_timeout',model='model',event_index=1))
            with self.assertRaisesRegex(ProviderError,'latest unrecovered'):
                b.recover_codex_timeout(failure,validation)


if __name__=='__main__':unittest.main()
