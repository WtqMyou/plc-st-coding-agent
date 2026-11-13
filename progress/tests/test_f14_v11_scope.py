"""Scope selection and cost gates prevent resuming other frameworks/models."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import f14_v11_core as s
import f14_v11_budget as b
from f14_v11_scope import selected_jobs,CONDITION
from stbench.providers.base import ProviderError

class Scope(unittest.TestCase):
    def test_only_20_custom_deepseek_jobs_are_selected(self):
        jobs=[]
        for framework,model in s.old.ARMS:
            for pid in s.tasks():jobs.append(dict(condition=framework+'_'+model,framework=framework,model_id=model,pid=pid))
        rows=selected_jobs(dict(jobs=jobs),CONDITION)
        self.assertEqual(len(rows),20);self.assertTrue(all(j['framework']=='custom' and j['model_id']=='deepseek-v4pro' for j in rows))
        with self.assertRaises(AssertionError):selected_jobs(dict(jobs=jobs),'codex_deepseek-v4pro')
    def test_budget_rejects_other_conditions_before_charging(self):
        with tempfile.TemporaryDirectory() as d,patch.object(b,'HISTORY',0),patch.object(b,'BASELINE',0):
            path=Path(d)/'ledger.json';before=dict(version=3,limit_cny=420,spent_cny=0,events=[],recoveries=[])
            state=dict(before,halted='',f14_v11_authorization=dict(study_plan_sha256='plan',total_cap_cny=420),active_experiment_scope=dict(condition=CONDITION))
            s.atomic_json(path,state)
            jobs=[dict(job_id=c+'/task',first_upper_cny=1,repair_upper_cny=1) for c in [CONDITION,'codex_deepseek-v4pro','custom_minimax-m27']]
            co=b.Coordinator(path,dict(sha256='plan',jobs=jobs),baseline=before)
            for j in jobs[1:]:
                view=co.view(j['job_id']);view.context=dict(job_id=j['job_id'],candidate_index=0);original=path.read_bytes()
                with self.assertRaises(ProviderError):view.reserve(.1)
                self.assertEqual(path.read_bytes(),original)
            j=jobs[0];view=co.view(j['job_id']);view.context=dict(job_id=j['job_id'],candidate_index=0);view.reserve(.1)
            self.assertEqual(len(co.read()['events']),1)

if __name__=='__main__':unittest.main()
