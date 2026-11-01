"""Real local HTTP exchanges verify deadlines without any vendor or paid request."""
import hashlib
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from stbench.billing import CampaignBudget
from stbench.codex_baseline import response_events
from stbench.providers.base import ProviderError
from stbench.transport import post,RequestDeadline,HTTPFailure,MeteredProvider,validate_response

ROOT=Path(__file__).resolve().parents[1]

def source_hash():
    return hashlib.sha256(b''.join(p.read_bytes() for p in sorted((ROOT/'stbench').rglob('*.py')))).hexdigest()

class Deadlines(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.requests=[]
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_POST(self):
                self.rfile.read(int(self.headers.get('Content-Length',0)))
                cls.requests.append(self.path)
                if self.path=='/missing':self.send_error(404);return
                self.send_response(200)
                self.send_header('Content-Type','text/event-stream' if self.path in ('/responses','/incomplete') else 'application/json')
                self.end_headers()
                try:
                    if self.path=='/delayed':time.sleep(.8)
                    if self.path.startswith('/slow'):
                        # Socket inactivity stays below the limit; only a total deadline can stop this.
                        for _ in range(60):self.wfile.write(b' ');self.wfile.flush();time.sleep(.05)
                    if self.path=='/incomplete':
                        self.wfile.write(('data: '+json.dumps(dict(type='response.incomplete',response=dict(
                            model='model',status='incomplete',output=[],usage=dict(input_tokens=2,output_tokens=8))))+'\n\n').encode())
                        return
                    body=(response_events('code','model',dict(input_tokens=2,output_tokens=3,total_tokens=5))
                          if self.path=='/responses' else json.dumps(dict(model='model',usage=dict(prompt_tokens=2,completion_tokens=3),
                          choices=[dict(finish_reason='stop',message=dict(content='code'))])).encode())
                    self.wfile.write(body)
                except OSError:pass
        cls.server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True);cls.thread.start()
        cls.url='http://127.0.0.1:'+str(cls.server.server_port)
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown();cls.server.server_close();cls.thread.join(2)
    def test_successful_chat_and_streamed_responses_keep_usage(self):
        for endpoint,protocol in [('/ok','chat'),('/responses','responses')]:
            r=post(self.url+endpoint,{},'local-test-only',3)
            parsed=validate_response(r,protocol,['model'])
            self.assertTrue(parsed['complete']);self.assertEqual(parsed['prompt_tokens'],2)
            self.assertEqual(parsed['completion_tokens'],3)
    def test_heartbeat_cannot_extend_total_deadline_or_trigger_retry(self):
        before=self.requests.count('/slow');started=time.monotonic()
        with self.assertRaises(RequestDeadline):post(self.url+'/slow',{},'local-test-only',.6)
        self.assertLess(time.monotonic()-started,1.8)
        self.assertEqual(self.requests.count('/slow')-before,1)
    def test_http_rejection_stays_a_typed_failure(self):
        with self.assertRaises(HTTPFailure) as error:post(self.url+'/missing',{},'local-test-only',3)
        self.assertEqual(error.exception.status,404)
    def test_incomplete_sse_retains_usage_for_billing(self):
        result=post(self.url+'/incomplete',{},'local-test-only',3)
        parsed=validate_response(result,'responses',['model'])
        self.assertFalse(parsed['complete']);self.assertEqual(parsed['completion_tokens'],8)
    def test_explicit_longer_timeout_accepts_a_delayed_complete_reply(self):
        with self.assertRaises(RequestDeadline):post(self.url+'/delayed',{},'local-test-only',.4)
        result=post(self.url+'/delayed',{},'local-test-only',2)
        self.assertTrue(validate_response(result,'chat',['model'])['complete'])
    def test_deadline_retains_charge_and_halts_the_budget_once(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'ledger.json','preflight')
            spec=dict(model='model',api_key_env='UNUSED',base_url=self.url+'/slow',
                input_cny_per_million=1,output_cny_per_million=2)
            p=MeteredProvider(spec,b,offline=True,timeout=.6,max_tokens=64)
            with self.assertRaises(RequestDeadline):p.generate([])
            state=b.read(allow_halted=True)
            self.assertEqual(len(state['events']),1);self.assertEqual(state['events'][0]['status'],'reserved')
            self.assertEqual(state['spent_cny'],state['events'][0]['reserved_cny'])
            self.assertEqual(state['halt_details']['category'],'request_timeout')
            with self.assertRaises(ProviderError):b.reserve(.01)
    def test_timeout_recovery_requires_fresh_linked_evidence_and_preserves_charge(self):
        with tempfile.TemporaryDirectory() as d:
            b=CampaignBudget(Path(d)/'ledger.json','preflight');b.reserve(.5)
            state=b.snapshot();started=state['events'][0]['created_at']-1
            error='Upstream TimeoutError; no automatic retry'
            record=dict(model='model',experiment_kind='live',stop_reason='provider_error',error=error,
                started_at=started,finished_at=started+181,attempts=[dict(provider_error=error,code='',
                prompt_tokens=0,completion_tokens=0,latency_s=180)])
            evidence=Path(d)/'failure.json';evidence.write_text(json.dumps(record))
            validation=Path(d)/'validation.json'
            proof=dict(passed=True,request_seconds=420,source_sha256='old')
            validation.write_text(json.dumps(proof));b.halt('Unconfirmed upstream result; reservation retained')
            with self.assertRaises(ProviderError):b.recover_timeout(evidence,request_seconds=420,validation_path=validation)
            proof['source_sha256']=source_hash();validation.write_text(json.dumps(proof))
            recovery=b.recover_timeout(evidence,request_seconds=420,validation_path=validation)
            self.assertEqual(b.snapshot()['events'],state['events']);self.assertEqual(b.snapshot()['spent_cny'],.5)
            self.assertTrue(Path(recovery['backup']).exists())
            b.reserve(.1);b.halt('Unconfirmed upstream result; reservation retained')
            # The new request's timestamp is later than this old failure's end.
            record['finished_at']=started+.5;evidence.write_text(json.dumps(record))
            with self.assertRaises(ProviderError):b.recover_timeout(evidence,request_seconds=420,validation_path=validation)

if __name__=='__main__':unittest.main()
