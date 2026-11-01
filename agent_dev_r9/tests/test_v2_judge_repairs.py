"""Standard typed literals, reference-independent FIFO properties and native deadlines."""
import copy
from pathlib import Path
import sys
import tempfile
import time
import unittest
from stbench.cli import problems,reference
from stbench.evaluation import local_tests
from stbench.modelcheck import check,InputSpace
from stbench.platforms import Backend
from stbench.portability import adapt,PROFILE
from stbench.schema import Problem
from stbench.st.frontend import compile_st,tokenize

class JudgeRepairs(unittest.TestCase):
    def test_typed_word_decimal_bool_real_and_signed_bit_patterns_execute(self):
        fields=[('status','WORD'),('shifted','WORD'),('signedValue','DINT'),('ready','BOOL'),('ratio','LREAL'),('signedHex','INT')]
        p=Problem.from_dict(dict(pid='typed-constants',source='selfmade',title='typed constants',difficulty='easy',requirements='literal values',
            variables=[dict(name=name,data_type=typ,direction='output') for name,typ in fields],
            test_cases=[dict(tc_id='literal-values',inputs={},expected=dict(status=32769,shifted=4,signedValue=-17,
                ready=True,ratio=.001,signedHex=-1))]))
        src='FUNCTION_BLOCK FB\nVAR_OUTPUT\n'+''.join(f'{name}:{typ};\n' for name,typ in fields)+'END_VAR\n'+'''
status:=WORD#16#8001;
shifted:=SHL(WORD#1,2);
signedValue:=DINT#-17;
ready:=BOOL#TRUE;
ratio:=LREAL#1e-3;
signedHex:=INT#16#FFFF;
END_FUNCTION_BLOCK'''
        result=local_tests(src,p)
        self.assertTrue(result.compiles,result.compile_errors)
        self.assertTrue(result.all_tests_passed,result.failure_summary)
    def test_invalid_typed_values_are_rejected(self):
        for literal in ['WORD#65536','BYTE#-1','BOOL#2','DINT#1.5','WORD#16#GG']:
            result=compile_st('FUNCTION_BLOCK FB VAR x:WORD; END_VAR x:='+literal+'; END_FUNCTION_BLOCK')
            self.assertTrue(any(d.level=='error' for d in result.diags),literal)
    def test_typed_lexing_preserves_line_numbers_and_leaves_comments_and_strings_alone(self):
        tokens,errors=tokenize("(* WORD#16#FFFF *)\n'WORD#16#FFFF'\nWORD#16#8001")
        self.assertFalse(errors)
        self.assertEqual(tokens[0].kind,'str');self.assertEqual(tokens[0].value,'WORD#16#FFFF')
        self.assertEqual((tokens[1].num,tokens[1].literal_type,tokens[1].line),(32769,'WORD',3))
    def test_fifo_mapping_keeps_raw_specs_and_all_original_expected_values(self):
        p=next(p for p in problems() if p.pid=='public-hard-04');before=copy.deepcopy(p.to_dict())
        q,src,mapping=adapt(p,reference(p),'codesys')
        self.assertEqual(p.to_dict(),before)
        self.assertEqual([c.expected for c in q.test_cases],[c.expected for c in p.test_cases])
        self.assertEqual(PROFILE,'portable-frame-v5')
        self.assertTrue(any('capacity' in s.ltl for s in q.specs if s.ltl))
        self.assertFalse(any(__import__('re').search(r'\bcap\b',s.ltl) for s in q.specs if s.ltl))
    def test_fifo_ltl_can_check_a_candidate_without_the_reference_local_cap(self):
        p=next(p for p in problems() if p.pid=='public-hard-04');p,_,_=adapt(p,reference(p),'codesys')
        src='FUNCTION_BLOCK FB\n'
        for direction,section in [('input','VAR_INPUT'),('inout','VAR_IN_OUT'),('output','VAR_OUTPUT')]:
            src+=section+'\n'+''.join(f'{v.name}:{v.data_type};\n' for v in p.variables if v.direction.value==direction)+'END_VAR\n'
        src+='elementCount:=0; status:=WORD#0; END_FUNCTION_BLOCK'
        result=check(src,{s.sid:s.ltl for s in p.specs if s.ltl},InputSpace(dict(
            enqueue=[False],dequeue=[False],reset=[True],capacity=[4])),max_depth=2,max_traces=20,max_seconds=1)
        self.assertFalse(result.error,result.error)
        self.assertTrue(all(s.holds for s in result.specs))
    def test_native_timeout_does_not_wait_forever_for_descendant_output_pipes(self):
        with tempfile.TemporaryDirectory() as d:
            backend=Backend(dict(platform_root=d,limits=dict(compile_seconds=3)))
            (Path(d)/'cache').mkdir()
            code='import subprocess,sys,time; subprocess.Popen([sys.executable,"-c","import time; time.sleep(20)"]); print("started",flush=True); time.sleep(20)'
            start=time.monotonic();rc,out,err=backend.run([sys.executable,'-c',code],Path(d))
            self.assertIsNone(rc);self.assertLess(time.monotonic()-start,5);self.assertIn('started',out)
    def test_native_success_keeps_exit_status_and_both_logs(self):
        with tempfile.TemporaryDirectory() as d:
            backend=Backend(dict(platform_root=d,limits=dict(compile_seconds=5)))
            (Path(d)/'cache').mkdir()
            rc,out,err=backend.run([sys.executable,'-c','import sys;print("out");print("err",file=sys.stderr)'],Path(d))
            self.assertEqual(rc,0);self.assertIn('out',out);self.assertIn('err',err)

if __name__=='__main__':unittest.main()
