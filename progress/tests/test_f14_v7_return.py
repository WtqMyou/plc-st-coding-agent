"""POU control flow and two boundary corrections; no model requests."""
import json
from pathlib import Path
import subprocess
import sys
import unittest
ROOT=Path(__file__).resolve().parents[2]
V7=ROOT/'progress/f14_v7_boundary_review'


def worker(code,pid,mode='functional'):
    p=subprocess.run([sys.executable,'-B','-X','utf8',str(V7/'judge_worker.py')],
        input=json.dumps(dict(source=code,pid=pid,mode=mode,seconds=30)),capture_output=True,text=True,encoding='utf-8',timeout=38)
    if p.returncode:raise AssertionError(p.stderr)
    return json.loads(p.stdout)


class ReturnSemantics(unittest.TestCase):
    def probe(self,body,scans,outputs=('count',)):
        source='FUNCTION_BLOCK FB VAR_INPUT stop:BOOL;END_VAR VAR_OUTPUT count:INT;afterCount:INT;END_VAR VAR idx:INT;END_VAR '+body+' END_FUNCTION_BLOCK'
        p=subprocess.run([sys.executable,'-B','-X','utf8',str(V7/'runtime_probe.py')],
            input=json.dumps(dict(source=source,scans=scans,outputs=list(outputs))),capture_output=True,text=True,encoding='utf-8',timeout=10)
        self.assertEqual(p.returncode,0,p.stderr);result=json.loads(p.stdout);self.assertTrue(result['ok'],result)
        return result['scans']
    def test_top_level_return_ends_current_invocation(self):
        self.assertEqual(self.probe('count:=1;RETURN;count:=99;',[{}]),[dict(count=1)])
    def test_nested_if_return_and_next_scan_retention(self):
        body='count:=count+1;IF stop THEN RETURN;END_IF;afterCount:=afterCount+1;'
        self.assertEqual(self.probe(body,[dict(stop=True),dict(stop=False),dict(stop=True)],('count','afterCount')),
            [dict(count=1,afterCount=0),dict(count=2,afterCount=1),dict(count=3,afterCount=1)])
    def test_return_inside_case(self):
        self.assertEqual(self.probe('CASE count OF 0:count:=3;RETURN;ELSE count:=4;END_CASE;count:=99;',[{}]),[dict(count=3)])
    def test_return_inside_for_unwinds_the_whole_pou(self):
        self.assertEqual(self.probe('count:=0;FOR idx:=1 TO 3 DO IF idx=2 THEN RETURN;END_IF;count:=count+1;END_FOR;count:=99;',[{}]),[dict(count=1)])
    def test_return_inside_while(self):
        self.assertEqual(self.probe('count:=0;WHILE count<3 DO count:=count+1;IF count=2 THEN RETURN;END_IF;END_WHILE;count:=99;',[{}]),[dict(count=2)])
    def test_return_inside_repeat(self):
        self.assertEqual(self.probe('count:=0;REPEAT count:=count+1;IF count=2 THEN RETURN;END_IF;UNTIL count=3 END_REPEAT;count:=99;',[{}]),[dict(count=2)])
    def test_exit_still_exits_only_the_loop(self):
        self.assertEqual(self.probe('count:=0;FOR idx:=1 TO 3 DO count:=count+1;EXIT;END_FOR;afterCount:=7;',[{}],('count','afterCount')),[dict(count=1,afterCount=7)])
    def test_original_average_answer_passes_without_code_change(self):
        code=(V7/'developer_candidates/public-medium-03.original.st').read_text(encoding='utf-8')
        result=worker(code,'public-medium-03')['result']
        self.assertEqual((result['tests_passed'],result['tests_total']),(21,21))
    def test_temperature_strict_threshold_fix_passes_all_cases(self):
        code=(V7/'developer_candidates/public-medium-04.developer_fix.st').read_text(encoding='utf-8')
        result=worker(code,'public-medium-04')['result']
        self.assertEqual((result['tests_passed'],result['tests_total']),(37,37))
    def test_original_temperature_retains_two_boundary_failures(self):
        code=(V7/'developer_candidates/public-medium-04.original.st').read_text(encoding='utf-8')
        result=worker(code,'public-medium-04')['result']
        self.assertEqual((result['tests_passed'],result['tests_total']),(35,37))


if __name__=='__main__':unittest.main()
