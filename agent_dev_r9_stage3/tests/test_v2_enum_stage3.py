"""Enumerations must execute correctly and still reject invalid ST."""
import unittest
from stbench.st.frontend import compile_st
from stbench.st.typecheck import typecheck
from stbench.st.interp import Interpreter
from stbench.harness.prompts import build_system_prompt


class EnumStage3(unittest.TestCase):
    def source(self, types='TYPE State : (Idle, Active, Done); END_TYPE', body='s:=Active; ok:=s=State.Active;', declaration='s:State;'):
        return types+' FUNCTION_BLOCK FB VAR_OUTPUT ok:BOOL; END_VAR VAR '+declaration+' END_VAR '+body+' END_FUNCTION_BLOCK'

    def run_program(self, source):
        result=typecheck(compile_st(source))
        self.assertTrue(result.ok, [d.to_dict() for d in result.diags])
        return Interpreter(result.pou,result.structs)

    def test_members_case_labels_qualified_and_unqualified_are_numeric(self):
        runner=self.run_program(self.source(body='CASE s OF Idle: s:=State.Active; ELSE s:=Done; END_CASE ok:=s=ACTIVE;'))
        runner.scan();self.assertTrue(runner.get_var('ok'));self.assertEqual(runner.get_var('s'),1)
        runner.scan();self.assertFalse(runner.get_var('ok'));self.assertEqual(runner.get_var('s'),2)

    def test_default_zero_member_overrides_first_nonzero_member(self):
        runner=self.run_program(self.source(types='TYPE State : (Idle:=3, Active:=0, Done:=5); END_TYPE'))
        self.assertEqual(runner.get_var('s'),0)
        runner.scan();runner.reset();self.assertEqual(runner.get_var('s'),0)

    def test_first_member_is_default_when_zero_absent(self):
        runner=self.run_program(self.source(types='TYPE State : (Idle:=7, Active:=9, Done); END_TYPE'))
        self.assertEqual(runner.get_var('s'),7)

    def test_type_and_variable_defaults_are_distinct(self):
        runner=self.run_program(self.source(types='TYPE State : (Idle, Active, Done) := Done; END_TYPE', declaration='s:state:=STATE.Active;'))
        self.assertEqual(runner.get_var('s'),1)

    def test_explicit_signed_values_base_type_and_automatic_successor(self):
        runner=self.run_program(self.source(types='TYPE State : (Idle:=-3, Active:=4, Done) SINT; END_TYPE', body='s:=Done; ok:=s=State.Done;'))
        runner.scan();self.assertEqual(runner.get_var('s'),5)

    def test_ambiguous_unqualified_member_is_rejected_but_namespace_is_supported(self):
        types='TYPE State:(Idle,Active); Other:(Idle,Run); END_TYPE'
        result=typecheck(compile_st(self.source(types=types)))
        # Active is unique, so the reference source remains valid.
        self.assertTrue(result.ok)
        bad=typecheck(compile_st(self.source(types=types,body='s:=Idle; ok:=FALSE;')))
        self.assertIn('E_ENUM_AMBIGUOUS',[d.code for d in bad.errors])
        self.run_program(self.source(types=types,body='s:=State.Idle; ok:=TRUE;'))

    def test_malformed_and_out_of_range_enum_declarations_fail(self):
        for types in ['TYPE State:(Idle,Idle); END_TYPE','TYPE State:(Idle,Active:=40000); END_TYPE',
                      'TYPE State:(Idle,Active) END_TYPE','TYPE State:(Idle,Active:=1.5); END_TYPE']:
            with self.subTest(types=types):self.assertFalse(compile_st(self.source(types=types)).ok)

    def test_readonly_members_and_nonexistent_members_fail(self):
        for body in ['Idle:=Active; ok:=TRUE;','State.Idle:=Active; ok:=TRUE;','s:=State.Unknown; ok:=TRUE;']:
            with self.subTest(body=body):self.assertFalse(typecheck(compile_st(self.source(body=body))).ok)

    def test_public_prompt_does_not_impose_edge_reset_on_every_task(self):
        self.assertIn('题面要求电平复位',build_system_prompt())
        self.assertIn('仅在题面明确要求上升沿',build_system_prompt())

    def test_nonstrict_enums_allow_native_supported_integer_operations(self):
        runner=self.run_program(self.source(body='s:=1; s:=s+1; ok:=s=2;'))
        runner.scan();self.assertEqual(runner.get_var('s'),2);self.assertTrue(runner.get_var('ok'))

    def test_strict_and_qualified_attributes_are_enforced_and_exported(self):
        from stbench.platforms import split_st
        types="{attribute 'strict'} {attribute 'qualified_only'} TYPE State:(Idle,Active); END_TYPE"
        source=self.source(types=types,body='s:=State.Active; ok:=s=State.Active;')
        self.run_program(source)
        self.assertIn("{attribute 'strict'}",split_st(source)['types'][0])
        for body in ('s:=Active; ok:=TRUE;','s:=s+1; ok:=TRUE;'):
            with self.subTest(body=body):self.assertFalse(typecheck(compile_st(self.source(types=types,body=body))).ok)


if __name__=='__main__':unittest.main()
