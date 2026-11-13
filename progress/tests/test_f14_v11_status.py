"""Public-only denominators and explicit stop/drain messages for the live page."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v11_core as s
from f14_v11_status import report,LABELS

class Status(unittest.TestCase):
    def test_drain_status_is_explicit_and_public_denominators_are_fixed(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);campaign=root/'run';campaign.mkdir();ledger=root/'ledger.json'
            before=dict(events=[],recoveries=[],spent_cny=0)
            state=dict(before,spent_cny=.1,halted='Unconfirmed request',f14_v11_authorization={},events=[dict(status='reserved',reserved_cny=.1,request=dict(job_id='custom_deepseek-v4pro/public-easy-01',candidate_index=0))])
            s.atomic_json(ledger,state);s.atomic_json(campaign/'ledger_before_study.json',before)
            s.atomic_json(campaign/'study_state.json',dict(state='running'))
            jobs=[dict(condition=c,pid=p) for c in LABELS for p in s.tasks()]
            with patch.object(s,'MIRROR',root/'mirror'),patch.object(s,'HISTORY',0),patch.object(s,'BASELINE',0):
                result=report(dict(campaign_root=str(campaign),budget_ledger_path=str(ledger)),dict(jobs=jobs,worst_reservation_cny=219.1572))
            self.assertIn('停止新增请求',result['display_state']);self.assertEqual(result['planned'],80)
            self.assertEqual(result['maximum_requests'],320);self.assertEqual(len(result['rows']),4)
            self.assertTrue(all(r['planned']==20 and r['assertions_total']==470 for r in result['rows']))

if __name__=='__main__':unittest.main()
