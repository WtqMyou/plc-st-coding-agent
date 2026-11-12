"""Native-grammar regression and exact integer/BOOL conversion checks."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest
ROOT=Path(__file__).resolve().parents[2]/'progress/f14_agent_v4_diagnostics'
spec=importlib.util.spec_from_file_location('tested_v4_formatter',ROOT/'formatting.py')
fmt=importlib.util.module_from_spec(spec);spec.loader.exec_module(fmt)

class DiagnosticFixTests(unittest.TestCase):
    def test_struct_dut_has_no_separator_before_end_type(self):
        for source in ('TYPE ST_A:STRUCT x:INT;END_STRUCT END_TYPE','TYPE ST_A:STRUCT x:INT;END_STRUCT;END_TYPE;'):
            result,changes=fmt.normalize(source)
            self.assertNotIn('END_STRUCT;',result);self.assertIn('END_TYPE;',result)
            self.assertEqual(fmt.normalize(result),(result,[]))
    def test_nested_field_separator_and_literal_comments_preserved(self):
        source="TYPE Outer:STRUCT inner:STRUCT x:INT;END_STRUCT; tail:INT;END_STRUCT;END_TYPE\n(* END_STRUCT; END_TYPE *)\nFUNCTION_BLOCK FB VAR text:STRING:='END_STRUCT; END_TYPE';END_VAR END_FUNCTION_BLOCK"
        fixed,_=fmt.normalize(source)
        self.assertIn('END_STRUCT; tail:INT;',fixed);self.assertIn('(* END_STRUCT; END_TYPE *)',fixed)
        self.assertIn("'END_STRUCT; END_TYPE'",fixed);self.assertIn('tail:INT;END_STRUCTEND_TYPE;',fixed.replace(' ',''))
    def probe(self,code,inputs,outputs):
        request=dict(source=code,scans=inputs,outputs=outputs)
        p=subprocess.run([sys.executable,'-B','-X','utf8',str(ROOT/'runtime_probe.py')],input=json.dumps(request),capture_output=True,text=True,encoding='utf-8',timeout=10)
        return p
    def test_generic_integer_bool_and_ltime_conversion_precision(self):
        code='''FUNCTION_BLOCK FB VAR_INPUT flag:BOOL;t:LTIME;END_VAR
VAR_OUTPUT x:INT;mask:WORD;n:ULINT;END_VAR
x:=TO_INT(flag);mask:=TO_WORD(TO_INT(flag));n:=TO_ULINT(t);END_FUNCTION_BLOCK'''
        p=self.probe(code,[dict(flag=False,t=1800000000000000),dict(flag=True,t=9007199254740993)],['x','mask','n'])
        self.assertEqual(p.returncode,0,p.stderr);r=json.loads(p.stdout);self.assertTrue(r['ok'],r)
        self.assertEqual(r['scans'],[dict(x=0,mask=0,n=1800000000000000),dict(x=1,mask=1,n=9007199254740993)])
    def test_unsupported_narrowing_and_real_are_not_silently_coerced(self):
        for expression in ('TO_UINT(-1)','TO_INT(REAL#1.9)'):
            code='FUNCTION_BLOCK FB VAR x:INT;END_VAR x:='+expression+';END_FUNCTION_BLOCK'
            p=self.probe(code,[{}],[])
            self.assertNotEqual(p.returncode,0);self.assertIn('Unsupported modeling:',p.stderr)
    def test_original_v3_formatting_and_study_files_still_frozen(self):
        code="import sys;sys.path.insert(0,'progress/tools');import f14_v3_core as s;s.verify(s.config())"
        p=subprocess.run([sys.executable,'-B','-X','utf8','-c',code],cwd=ROOT.parents[1],capture_output=True,text=True,encoding='utf-8',timeout=15)
        self.assertEqual(p.returncode,0,p.stderr)

if __name__=='__main__':unittest.main()
