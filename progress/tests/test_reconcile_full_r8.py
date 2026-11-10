"""Billing-only correction; original input state and evidence stay untouched."""
import copy
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import reconcile_full_r8_provider as r
class Settlement(unittest.TestCase):
    def inputs(self):
        review=r.old.load(r.csv_review.DEST/'review.json')
        before=r.old.load(r.csv_review.ROOT/'ledger_at_provider_log_review_20261110.json')
        return before,review
    def test_fee_and_prefix(self):
        before,review=self.inputs();original=copy.deepcopy(before)
        after,change=r.settled_state(before,review)
        self.assertEqual(before,original);self.assertEqual(before['events'][:450],after['events'][:450])
        self.assertEqual(before['recoveries'],after['recoveries']);self.assertEqual(after['spent_cny'],39.831304)
        self.assertEqual(after['events'][450]['accounted_cny'],.115908);self.assertEqual(change['released_reserve_cny'],.314439)
    def test_stays_stopped_and_no_new_requests(self):
        before,review=self.inputs();after,_=r.settled_state(before,review)
        self.assertEqual(len(after['events']),451);self.assertEqual(after['halted'],r.PENDING)
        self.assertEqual(after['events'][450]['metadata']['finish_reason'],'not_recovered')
    def test_different_request_is_rejected(self):
        before,review=self.inputs();review['match']['local_request_id']='different'
        with self.assertRaises(AssertionError):r.settled_state(before,review)
    def test_wrong_tokens_are_rejected(self):
        before,review=self.inputs();review['match']['completion_tokens']+=1
        with self.assertRaises(AssertionError):r.settled_state(before,review)
    def test_wrong_fee_is_rejected(self):
        before,review=self.inputs();review['amounts']['provider_billed_cny']='0.12'
        with self.assertRaises(AssertionError):r.settled_state(before,review)
    def test_duplicate_settlement_is_rejected(self):
        before,review=self.inputs();after,_=r.settled_state(before,review)
        with self.assertRaises(AssertionError):r.settled_state(after,review)
    def test_changed_baseline_is_rejected(self):
        before,review=self.inputs();before['spent_cny']+=.1
        with self.assertRaises(AssertionError):r.settled_state(before,review)

if __name__=='__main__':unittest.main()
