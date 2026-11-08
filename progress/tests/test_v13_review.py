import copy
import math
from pathlib import Path
import sys
import unittest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO/'progress/v13'))
import revision as v
from stbench.schema import Problem, TestCase
from stbench.evaluation import local_tests
from stbench.ltl import evaluate
from stbench.modelcheck import _atom_evaluator


class ReviewRevisionTests(unittest.TestCase):
    def task(self, pid):
        return next(p for p in v.problems() if p.pid == pid)

    def holds(self, pid, sid, trace):
        p = self.task(pid)
        return evaluate(next(s.ltl for s in p.specs if s.sid == sid), trace,
                        _atom_evaluator({x.name.lower(): x.data_type for x in p.variables}, {})).holds

    def test_all_531_reference_cases_and_interfaces(self):
        results = [local_tests(src, q) for p in v.problems() for q, src, _ in [v.adapt(p)]]
        self.assertTrue(all(r.compiles and r.all_tests_passed for r in results))
        self.assertEqual(sum(r.tests_passed for r in results), 531)

    def test_original_fifo_reference_is_rejected_by_new_array_assertions(self):
        q, _, _ = v.adapt(self.task('self-hard-03'))
        old = (v.ENGINE/'datasets/selfmade/tests/self-hard-03.reference.st').read_text('utf-8')
        result = local_tests(old, q)
        self.assertEqual([c.tc_id for c in result.cases if not c.passed], ['q8', 'q9'])

    def test_fifo_full_pop_then_push_and_empty_compaction(self):
        p = self.task('self-hard-03')
        p.test_cases = []
        queue = []
        def case(push=False, pop=False, item=0):
            if pop and queue: queue.pop(0)
            if push and len(queue) < 8: queue.append(item)
            p.test_cases.append(TestCase(str(len(p.test_cases)), dict(pushEn=push, popEn=pop, pushItem=item),
                dict(count=len(queue), head=queue[0] if queue else 0, full=len(queue)==8,
                     empty=not queue, fifo=queue+[0]*(8-len(queue)))))
        for item in range(1, 9): case(push=True, item=item); case()
        case(push=True, item=99); case()  # Full push is ignored.
        case(push=True, pop=True, item=9); case()  # Pop frees a slot first.
        for _ in range(9): case(pop=True); case()
        q, src, _ = v.adapt(p)
        self.assertTrue(local_tests(src, q).all_tests_passed)

    def test_pi_consecutive_switch_bad_outputs_rejected(self):
        prev = dict(normalmode=False, mode=1, flowsp=10., valvecommand=9.2,
                    manualflowsp=10., manualvalve=99., fault=False, resetbtn=False)
        bad = dict(prev, mode=2, flowsp=30., valvecommand=99., manualflowsp=30.)
        self.assertFalse(self.holds('self-hard-07', 'S8', [prev, bad]))
        good = dict(bad, flowsp=10., valvecommand=9.2)
        self.assertTrue(self.holds('self-hard-07', 'S8', [prev, good]))

    def test_pi_non_cascade_switch_holds_valve_not_flow(self):
        prev = dict(normalmode=False, mode=2, flowsp=10.8, valvecommand=42.2,
                    manualflowsp=10., manualvalve=35., fault=False, resetbtn=False)
        good = dict(prev, mode=1, flowsp=10.)
        self.assertTrue(self.holds('self-hard-07', 'S7', [prev, good]))
        self.assertFalse(self.holds('self-hard-07', 'S7', [prev, dict(good, valvecommand=35.)]))

    def test_pi_first_scan_and_reset_do_not_require_history_hold(self):
        first = dict(normalmode=False, mode=2, flowsp=10., valvecommand=20.,
                     manualflowsp=10., manualvalve=20., fault=False, resetbtn=False)
        self.assertTrue(self.holds('self-hard-07', 'S8', [first]))
        reset = dict(first, mode=1, resetbtn=True, valvecommand=80., manualvalve=80.)
        self.assertTrue(self.holds('self-hard-07', 'S7', [first, reset]))

    def test_mask_rejects_dropped_and_invented_bits(self):
        for old, current, actual, expected in [(4,8,8,False),(4,2,6,True),(4,2,7,False),(8,1,9,True),(15,0,15,True),(0,1,1,True),(0,16,0,False)]:
            trace = [dict(triplatched=True, latchedcausemask=old, currentcausemask=old),
                     dict(triplatched=True, latchedcausemask=actual, currentcausemask=current)]
            self.assertEqual(self.holds('self-hard-06', 'S13', trace), expected)

    def test_new_numeric_property_ids_are_executable(self):
        for pid in ['self-medium-05', 'self-medium-06']:
            q, _, _ = v.adapt(self.task(pid))
            self.assertTrue(next(s.ltl for s in q.specs if s.sid == 'S10'))
        self.assertEqual(sum(bool(s.ltl) for p in v.problems() for s in v.adapt(p)[0].specs), 196)

    def test_review_state_not_overwritten_as_pending_or_approved(self):
        for pid in v.FIVE:
            q, _, _ = v.adapt(self.task(pid))
            self.assertEqual(q.provenance['human_process_review']['status'], 'corrected_pending_rereview')
            self.assertFalse(q.provenance['human_process_review']['approved'])

    def test_invalid_mc_budget_rejected(self):
        for value in [0, -1, float('inf'), float('nan'), True, '30']:
            with self.assertRaises(ValueError): v.adapt(self.task('self-hard-05'), mc_seconds=value)

    def test_adaptation_does_not_change_raw_task(self):
        for p in v.problems():
            before = copy.deepcopy(p.to_dict())
            v.adapt(p)
            self.assertEqual(p.to_dict(), before)


if __name__ == '__main__': unittest.main()
