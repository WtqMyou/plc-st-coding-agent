"""Native byte context, legacy character compatibility and recovery evidence integrity."""
import json
from pathlib import Path
import subprocess
import sys
import unittest
ROOT=Path(__file__).resolve().parents[2]
EXT=ROOT/'progress/f14_v5_string_recovery'


def probe(source,scans,outputs):
    return subprocess.run([sys.executable,'-B','-X','utf8',str(EXT/'local_probe.py')],
        input=json.dumps(dict(source=source,scans=scans,outputs=outputs)),capture_output=True,text=True,encoding='utf-8',timeout=15)


class ConversionRecovery(unittest.TestCase):
    def test_ascii_byte_context_is_zero_based_with_null_terminator(self):
        source="FUNCTION_BLOCK FB VAR_INPUT txt:STRING(8);END_VAR VAR_OUTPUT first:INT;dot:INT;last:INT;END_VAR first:=BYTE_TO_INT(txt[0]);dot:=BYTE_TO_INT(txt[1]);last:=BYTE_TO_INT(txt[2]);END_FUNCTION_BLOCK"
        p=probe(source,[dict(txt='1.'),dict(txt='9.')],['first','dot','last'])
        self.assertEqual(p.returncode,0,p.stderr);r=json.loads(p.stdout);self.assertTrue(r['ok'],r)
        self.assertEqual(r['scans'],[dict(first=49,dot=46,last=0),dict(first=57,dot=46,last=0)])
    def test_course_character_assignment_keeps_its_original_view(self):
        source="FUNCTION_BLOCK FB VAR_INPUT txt:STRING(8);END_VAR VAR_OUTPUT ch:STRING;END_VAR ch:=txt[1];END_FUNCTION_BLOCK"
        p=probe(source,[dict(txt='1.')],['ch']);self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(json.loads(p.stdout)['scans'],[dict(ch='1')])
    def test_beyond_terminator_is_unresolved_instead_of_a_python_crash(self):
        source="FUNCTION_BLOCK FB VAR_INPUT txt:STRING(8);END_VAR VAR_OUTPUT x:INT;END_VAR x:=BYTE_TO_INT(txt[3]);END_FUNCTION_BLOCK"
        p=probe(source,[dict(txt='1.')],['x'])
        self.assertNotEqual(p.returncode,0);self.assertIn('Unsupported modeling:',p.stderr)
        self.assertNotIn('ValueError:',p.stderr)
    def test_non_ascii_code_page_is_not_guessed(self):
        source="FUNCTION_BLOCK FB VAR_INPUT txt:STRING(8);END_VAR VAR_OUTPUT x:INT;END_VAR x:=BYTE_TO_INT(txt[0]);END_FUNCTION_BLOCK"
        p=probe(source,[dict(txt='中')],['x'])
        self.assertNotEqual(p.returncode,0);self.assertIn('non-ASCII STRING code page',p.stderr)
    def test_actual_failed_candidate_returns_all_cases_without_worker_failure(self):
        source=Path('E:/PLC_Dev/evidence/real_experiments/f14_v5_public_pilot_20261112/jobs/custom_deepseek-v4pro/public-medium-08.candidate_02.st').read_text(encoding='utf-8')
        p=subprocess.run([sys.executable,'-B','-X','utf8',str(EXT/'judge_worker.py')],
            input=json.dumps(dict(source=source,pid='public-medium-08',mode='functional')),capture_output=True,text=True,encoding='utf-8',timeout=30)
        self.assertEqual(p.returncode,0,p.stderr);r=json.loads(p.stdout)
        self.assertEqual(r['result']['tests_total'],14);self.assertEqual(len(r['result']['cases']),14)
        self.assertNotIn('invalid literal for int()',p.stdout)
        self.assertNotIn('"expected":',r['feedback'])
    def test_native_simulator_agrees_with_numeric_context(self):
        p=Path('E:/PLC_Dev/evidence/incoming_reviews/f14_v5_string_probe_20261112_v2/result.json')
        result=json.loads(p.read_text(encoding='utf-8'))
        self.assertTrue(result['native_execution']);self.assertEqual(result['status'],'passed')
        values=result['final_values_normalized']
        self.assertEqual([values[k] for k in ('probe.firstByte','probe.dotByte','probe.endByte')],['49','46','0'])
        self.assertEqual(result['cleanup_errors'],[])
    def test_frozen_study_and_budget_still_match_baseline_before_recovery(self):
        program="import sys;sys.path.insert(0,'progress/tools');import f14_v5_core as s;s.verify(s.config())"
        p=subprocess.run([sys.executable,'-B','-X','utf8','-c',program],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',timeout=20)
        self.assertEqual(p.returncode,0,p.stderr)


if __name__=='__main__':unittest.main()
