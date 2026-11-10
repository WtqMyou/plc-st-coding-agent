"""No billable endpoints: event parsing, partial traces and wall deadlines."""
import http.client
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from unittest.mock import patch
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import full_r8b_transport as t
from stbench.transport import IdentityFailure
from stbench.providers.base import ProviderError
MODEL='fixture-model'
DONE=dict(type='response.completed',response=dict(model=MODEL,status='completed',
          usage=dict(input_tokens=1,output_tokens=2),output=[dict(type='message',content=[dict(type='output_text',text='FUNCTION_BLOCK FB END_FUNCTION_BLOCK')])]))
def frame(obj):return ('data: '+json.dumps(obj)+'\n\n').encode()
class Response:
    def __init__(self,body,mime='text/event-stream',broken=False):
        self.body=io.BytesIO(body);self.headers={'Content-Type':mime};self.status=200;self.broken=broken
    def __enter__(self):return self
    def __exit__(self,*args):pass
    def readline(self):
        value=self.body.readline()
        if not value and self.broken:raise http.client.IncompleteRead(b'partial',10)
        return value
    def read(self,size=-1):return self.body.read(size)
class Budget:
    def __init__(self):self.events=[];self.halted=''
    def reserve(self,amount,request=None):self.events.append(dict(status='reserved'));return len(self.events)-1
    def settle(self,index,cost,metadata=None):self.events[index].update(status='settled',cost=cost)
    def halt(self,reason,details=None):self.halted=reason
class HTTPAdapter(unittest.TestCase):
    def exchange(self,d,response):
        with patch.object(t.urllib.request,'urlopen',return_value=response) as mock:
            result=t.exchange('https://offline.invalid/v1/responses',{},'PRIVATE_FIXTURE_KEY',1,d)
            self.assertEqual(mock.call_count,1)
        return result
    def test_terminal_returns_before_broken_tail(self):
        with tempfile.TemporaryDirectory() as d:
            result=self.exchange(d,Response(frame(DONE),broken=True))
            self.assertEqual(result,DONE['response'])
            diag=json.loads((Path(d)/'diagnostic.json').read_text())
            self.assertTrue(diag['completed_terminal']);self.assertEqual(diag['automatic_retries'],0)
    def test_terminal_without_blank_separator_returns_immediately(self):
        with tempfile.TemporaryDirectory() as d:
            result=self.exchange(d,Response(frame(DONE).rstrip(b'\n')+b'\n',broken=True))
            self.assertEqual(result,DONE['response'])
    def test_null_and_comment_are_not_success_without_terminal(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(t.ProtocolFailure):self.exchange(d,Response(b': heartbeat\n\ndata: null\n\n'))
            diag=json.loads((Path(d)/'diagnostic.json').read_text())
            self.assertFalse(diag['completed_terminal']);self.assertEqual(diag['ignored_non_object_events'],1)
    def test_null_before_terminal_preserves_output(self):
        with tempfile.TemporaryDirectory() as d:
            result=self.exchange(d,Response(b'data: null\n\n'+frame(DONE)))
            self.assertEqual(result,DONE['response'])
    def test_multiline_data_event(self):
        with tempfile.TemporaryDirectory() as d:
            text=json.dumps(DONE,indent=2)
            result=self.exchange(d,Response(('\n'.join('data: '+line for line in text.splitlines())+'\n\n').encode()))
            self.assertEqual(result,DONE['response'])
    def test_compatible_missing_separators(self):
        with tempfile.TemporaryDirectory() as d:
            raw=frame(dict(type='response.created')).rstrip(b'\n')+b'\n'+frame(DONE)
            self.assertEqual(self.exchange(d,Response(raw)),DONE['response'])
    def test_partial_read_keeps_bytes_and_exception_type(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(ProviderError):self.exchange(d,Response(b': open\n\n',broken=True))
            self.assertTrue((Path(d)/'http_body.bin').read_bytes().endswith(b'partial'))
            diag=json.loads((Path(d)/'diagnostic.json').read_text())
            self.assertEqual(diag['exception_type'],'IncompleteRead');self.assertFalse(diag['completed_terminal'])
    def test_invalid_json_is_named_and_preserved(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(t.ProtocolFailure):self.exchange(d,Response(b'data: {broken\n\n'))
            self.assertIn(b'{broken',(Path(d)/'http_body.bin').read_bytes())
            self.assertEqual(json.loads((Path(d)/'diagnostic.json').read_text())['exception_type'],'ProtocolFailure')
    def test_missing_response_object_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(t.ProtocolFailure):self.exchange(d,Response(frame(dict(type='response.completed',response=None))))
    def test_done_only_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(t.ProtocolFailure):self.exchange(d,Response(b'data: [DONE]\n\n'))
    def test_json_chat_body(self):
        with tempfile.TemporaryDirectory() as d:
            result=self.exchange(d,Response(json.dumps(dict(model=MODEL,choices=[])).encode(),'application/json'))
            self.assertEqual(result['model'],MODEL)
    def test_upstream_error_does_not_leak_body_into_diagnostic(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(t.ProtocolFailure):self.exchange(d,Response(frame(dict(type='error',message='PRIVATE_FIXTURE_KEY'))))
            self.assertIn(b'PRIVATE_FIXTURE_KEY',(Path(d)/'http_body.bin').read_bytes())
            self.assertNotIn('PRIVATE_FIXTURE_KEY',(Path(d)/'diagnostic.json').read_text())
    def test_identity_rejection_keeps_reservation(self):
        budget=Budget();spec=dict(model=MODEL,accepted_models=[MODEL],api_key_env='DMXAPI_API_KEY',
            generation_protocol='responses',input_cny_per_million=1,output_cny_per_million=1,base_url='https://offline.invalid/v1')
        bad=dict(DONE['response'],model='different')
        with tempfile.TemporaryDirectory() as d,patch.dict(os.environ,DMXAPI_API_KEY='PRIVATE_FIXTURE_KEY'),patch.object(t,'post',return_value=bad) as mock:
            provider=t.MeteredProvider(spec,budget,protocol='responses');provider.diagnostic_dir=Path(d)
            with self.assertRaises(IdentityFailure):provider.generate([dict(role='user',content='fixture')])
            self.assertEqual(mock.call_count,1);self.assertEqual(budget.events[0]['status'],'reserved');self.assertTrue(budget.halted)
    def test_explicit_incomplete_is_known_cost_not_retry(self):
        budget=Budget();spec=dict(model=MODEL,accepted_models=[MODEL],api_key_env='DMXAPI_API_KEY',
            input_cny_per_million=1,output_cny_per_million=1,base_url='https://offline.invalid/v1')
        incomplete=dict(DONE['response'],status='incomplete',output=[])
        with tempfile.TemporaryDirectory() as d,patch.dict(os.environ,DMXAPI_API_KEY='PRIVATE_FIXTURE_KEY'),patch.object(t,'post',return_value=incomplete) as mock:
            provider=t.MeteredProvider(spec,budget,protocol='responses');provider.diagnostic_dir=Path(d)
            with self.assertRaisesRegex(ProviderError,'Generation incomplete/empty:'):provider.generate([dict(role='user',content='fixture')])
            self.assertEqual(mock.call_count,1);self.assertEqual(budget.events[0]['status'],'settled');self.assertFalse(budget.halted)
    def test_isolated_worker_receives_completed_stream_without_tail_close(self):
        class Handler(BaseHTTPRequestHandler):
            requests=0
            def do_POST(self):
                type(self).requests+=1;self.rfile.read(int(self.headers.get('Content-Length',0)))
                self.send_response(200);self.send_header('Content-Type','text/event-stream');self.end_headers()
                try:self.wfile.write(frame(DONE));self.wfile.flush();time.sleep(3)
                except (BrokenPipeError,ConnectionResetError):pass
            def log_message(self,*args):pass
        server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        threading.Thread(target=server.serve_forever,daemon=True).start()
        try:
            with tempfile.TemporaryDirectory() as d:
                started=time.monotonic()
                result=t.post(f'http://127.0.0.1:{server.server_port}/v1/responses',{},'fixture',2,d)
                self.assertEqual(result,DONE['response']);self.assertLess(time.monotonic()-started,2)
                self.assertEqual(Handler.requests,1)
                self.assertEqual((Path(d)/'http_body.bin').read_bytes(),frame(DONE).rstrip(b'\n')+b'\n')
                self.assertEqual(json.loads((Path(d)/'diagnostic.json').read_text())['worker_returncode'],0)
        finally:server.shutdown();server.server_close()
    def test_whole_exchange_deadline_has_no_retry(self):
        class Handler(BaseHTTPRequestHandler):
            requests=0
            def do_POST(self):
                type(self).requests+=1;self.rfile.read(int(self.headers.get('Content-Length',0)))
                self.send_response(200);self.send_header('Content-Type','text/event-stream');self.end_headers()
                try:self.wfile.write(b': waiting\n\n');self.wfile.flush();time.sleep(2)
                except (BrokenPipeError,ConnectionResetError):pass
            def log_message(self,*args):pass
        server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            with tempfile.TemporaryDirectory() as d:
                started=time.monotonic()
                with self.assertRaises(t.RequestDeadline):t.post(f'http://127.0.0.1:{server.server_port}/v1/responses',{},'fixture',.4,d)
                self.assertLess(time.monotonic()-started,1.5);self.assertLessEqual(Handler.requests,1)
                diag=json.loads((Path(d)/'diagnostic.json').read_text());self.assertEqual(diag['exception_type'],'RequestDeadline')
        finally:server.shutdown();server.server_close()
    def test_existing_trace_is_never_reused(self):
        with tempfile.TemporaryDirectory() as d:
            self.exchange(d,Response(frame(DONE)))
            before=(Path(d)/'http_body.bin').read_bytes()
            with self.assertRaises(t.ProtocolFailure):self.exchange(d,Response(frame(DONE)))
            self.assertEqual(before,(Path(d)/'http_body.bin').read_bytes())

if __name__=='__main__':unittest.main()
