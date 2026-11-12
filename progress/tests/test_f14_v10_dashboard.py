"""Check overnight status has fixed full denominators and separate public/self results."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v10_core as s
from f14_v10_dashboard import report,LABELS

class StatusPage(unittest.TestCase):
    def test_running_report_separates_groups_and_keeps_all_denominators(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);campaign=root/'run';campaign.mkdir();mirror=root/'mirror'
            before=dict(events=[],recoveries=[],spent_cny=0,limit_cny=210)
            ledger=dict(before,spent_cny=.1,limit_cny=420)
            condition='custom_deepseek-v4pro';pid='public-easy-01'
            ledger['events']=[dict(status='settled',reserved_cny=.8,accounted_cny=.1,request=dict(job_id=condition+'/'+pid))]
            s.atomic_json(root/'ledger.json',ledger);s.atomic_json(campaign/'ledger_before_study.json',before)
            s.atomic_json(campaign/'study_state.json',dict(state='running',completed=1,active_jobs=[]))
            attempt=dict(functional_pass=True,native_pass=True,complete_code=True,tests_passed=10,verification_status='truncated')
            record=dict(job_done=True,pid=pid,condition=condition,attempts=[attempt],best_attempt=0)
            s.atomic_json(campaign/'jobs'/condition/(pid+'.json'),record)
            jobs=[dict(condition=c,pid=p) for c in LABELS for p in s.tasks()]
            with patch.object(s,'MIRROR',mirror),patch.object(s,'HISTORY',0),patch.object(s,'BASELINE',0):
                result=report(dict(campaign_root=str(campaign),budget_ledger_path=str(root/'ledger.json')),dict(jobs=jobs,worst_reservation_cny=289.206680))
            self.assertEqual((result['planned'],result['recorded'],result['maximum_requests']),(140,1,560))
            group=result['rows'][0];self.assertEqual(group['groups']['public']['final_functional'],1)
            self.assertEqual(group['groups']['self_built']['final_functional'],0)
            self.assertEqual(group['assertions_total'],946)
            self.assertEqual(group['groups']['public']['assertions_total'],470)
            self.assertEqual(group['groups']['self_built']['assertions_total'],476)
            self.assertTrue(result['original_events_preserved']);self.assertFalse(result['completion_audit_passed'])
            html=(campaign/'status.html').read_text(encoding='utf-8');self.assertIn('140',html);self.assertIn('420',html)
            self.assertTrue((mirror/'jobs'/condition/(pid+'.json')).exists())

if __name__=='__main__':unittest.main()
