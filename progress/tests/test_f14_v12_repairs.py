import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v12_core as s
from v12_repairs import apply,REPAIR_MODE

class RepairTests(unittest.TestCase):
    def test_exact_replay_and_ambiguous_anchor_rejected(self):
        source,meta=apply(json.dumps({'edits':[{'old':'a:=1;','new':'a:=2;'}]}),'a:=1;b:=3;')
        self.assertEqual(source,'a:=2;b:=3;');self.assertEqual(meta['mode'],'model_exact_edits')
        for base in ('a:=1;a:=1;','b:=3;'):
            with self.assertRaises(ValueError):apply(json.dumps({'edits':[{'old':'a:=1;','new':'a:=2;'}]}),base)
    def test_architecture_replacement_is_exact_model_text(self):
        code='FUNCTION_BLOCK FB END_FUNCTION_BLOCK'
        self.assertEqual(apply(json.dumps({'replace_program':code}),'old')[0],code)
        with self.assertRaises(ValueError):apply('{"edits":[]}','old')
    def test_fresh_first_requests_have_no_saved_answer_and_repair_override(self):
        for pid in s.tasks():
            messages=s.messages(dict(pid=pid));self.assertEqual(len(messages),2)
            self.assertNotIn('edits',messages[0]['content']);self.assertNotIn('expected_any',str(messages))
            self.assertNotIn('reference.st',str(messages))
        a=dict(code='candidate only',feedback='public actual replay')
        messages=s.repair_messages(dict(pid='public-hard-05'),a,[])
        self.assertIn(REPAIR_MODE,messages[0]['content']);self.assertEqual(messages[-2]['content'],a['code'])
    def test_variant_abi_integer_real_string_and_lower_bound(self):
        # This generic read/write probe supplies no FIFO algorithm.
        script='''import sys,json
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1])/'release'))
from stbench.st.frontend import compile_st
from stbench.st.typecheck import typecheck
from stbench.st.interp import Interpreter,VariantValue,ArrayValue
code="FUNCTION_BLOCK Probe VAR_IN_OUT data:VARIANT;value:VARIANT;END_VAR VAR_OUTPUT low:DINT;high:DINT;END_VAR low:=LOWER_BOUND(data,1);high:=UPPER_BOUND(data,1);data[low]:=value;value:=data[high];END_FUNCTION_BLOCK"
p=typecheck(compile_st(code));assert p.ok,[d.to_dict() for d in p.diags]
for values,item in [([1,2],9),([1.5,2.5],9.5),(['one','two'],'new')]:
 e=Interpreter(p.pou,p.structs);e.set_var('data',VariantValue(ArrayValue(-2,-1,values.copy()),'ARRAY[-2..-1]'));e.set_var('value',item);e.scan()
 assert e.get_var('low')==-2 and e.get_var('high')==-1
 assert e.get_var('value').value==values[-1]
 assert e.get_var('data').value.items[0]==item
print('PASS')'''
        import subprocess
        p=subprocess.run([sys.executable,'-B','-X','utf8','-c',script,str(s.CONFIG.parent)],capture_output=True,text=True)
        self.assertEqual(p.returncode,0,p.stderr)

if __name__=='__main__':unittest.main()
