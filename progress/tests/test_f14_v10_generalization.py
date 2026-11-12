"""Full-scope, public-only arithmetic and corrected scan-control-flow controls."""
import json
from pathlib import Path
import subprocess
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v10_core as s
from public_time_bounds import derive

class FullScope(unittest.TestCase):
    def test_all_35_original_tasks_and_946_assertions_are_in_scope(self):
        self.assertEqual(len(s.tasks()),35)
        self.assertEqual(sum(p.startswith('public-') for p in s.tasks()),20)
        self.assertEqual(sum(len(t['test_cases']) for p,t in s.tasks().items() if p.startswith('public-')),470)
        self.assertEqual(sum(len(t['test_cases']) for p,t in s.tasks().items() if not p.startswith('public-')),476)
        cfg=s.config();self.assertEqual(cfg['study']['max_requests'],560);self.assertEqual(cfg['budget_cny'],420)
        self.assertEqual(cfg['limits']['max_candidates'],4)
        self.assertEqual(cfg['concurrency']['max_jobs'],8)
    def test_generic_time_rules_are_exact_and_not_task_id_specific(self):
        for text,value in [('more than 5s',5001),('at least 500 ms',500),('reaches 500 hours',1800000000),
                           ('exceeds 0.0005 seconds',1),('at least 0.0005 seconds',1),('more than 2 days',172800001)]:
            self.assertEqual(derive(text)[0]['first_satisfying_tick_ms'],value,text)
        self.assertEqual(derive('more than 5s',.000001)[0]['first_satisfying_tick_ms'],5000.000001)
        with self.assertRaises(ValueError):derive('more than 5s',0)
        self.assertEqual(derive('No explicit duration threshold.'),[])
        source=(s.CONFIG.parent/'public_time_bounds.py').read_text(encoding='utf-8')
        self.assertNotIn('public-medium',source);self.assertNotIn('test_cases',source);self.assertNotIn('reference.st',source)
    def test_public_analysis_has_same_content_for_both_frameworks(self):
        for pid in s.tasks():
            custom=s.messages(dict(pid=pid,framework='custom'));codex=s.messages(dict(pid=pid,framework='codex'))
            self.assertEqual(custom,codex)
            self.assertIn('Public-text discrete-time boundary arithmetic',custom[0]['content'])
            self.assertNotIn('"expected":',json.dumps(custom,ensure_ascii=False))
    def test_public_clause_index_locates_full_original_lines_without_duplication(self):
        from v10_contracts import clauses,clause_index
        for pid in s.tasks():
            user=s.messages(dict(pid=pid))[1]['content']
            numbered=clauses(user);index=clause_index(user)
            self.assertEqual(len(numbered),len(index))
            for row,clause in zip(index,numbered):
                self.assertEqual(user[row['start_character']:row['end_character_exclusive']],clause['text'])
    def test_return_unwinds_entire_pou_and_preserves_next_scan_state(self):
        source='FUNCTION_BLOCK FB VAR_INPUT stop:BOOL;END_VAR VAR_OUTPUT count:INT;tail:INT;END_VAR VAR idx:INT;END_VAR count:=count+1;FOR idx:=1 TO 3 DO IF stop THEN RETURN;END_IF;END_FOR;tail:=tail+1;END_FUNCTION_BLOCK'
        proc=subprocess.run([sys.executable,'-B','-X','utf8',str(s.CONFIG.parent/'runtime_probe.py')],
            input=json.dumps(dict(source=source,scans=[dict(stop=True),dict(stop=False),dict(stop=True)],outputs=['count','tail'])),
            capture_output=True,text=True,encoding='utf-8',timeout=15)
        self.assertEqual(proc.returncode,0,proc.stderr)
        self.assertEqual(json.loads(proc.stdout)['scans'],[dict(count=1,tail=0),dict(count=2,tail=1),dict(count=3,tail=1)])

if __name__=='__main__':unittest.main()
