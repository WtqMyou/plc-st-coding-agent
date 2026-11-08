"""r2 entrypoints validate complete-output cases before entering the frozen judge."""
import copy
import r2_revision
from stbench import evaluation as base
from stbench.st.driver import CaseResult, StageResult

JUDGE_VERSION = 'r2-full-output-contract-v1'


def prepare(problem):
    """Reject invalid test data, regardless of case mode; input is never mutated."""
    outputs = {v.name.lower():v.name for v in problem.variables if v.direction.value in ('output','inout')}
    normalized = copy.deepcopy(problem)
    normalized.provenance['judge_contract_version'] = JUDGE_VERSION
    issues = []
    for case in normalized.test_cases:
        if not case.expect_full:
            continue
        missing = sorted(set(outputs)-{name.lower() for name in case.expected})
        if missing:
            issues.append(dict(tc_id=case.tc_id, missing_outputs=[outputs[name] for name in missing]))
        else:
            case.expected = {outputs.get(name.lower(), name):value for name,value in case.expected.items()}
    if issues:
        return None, StageResult(compiles=False, tests_total=len(problem.test_cases),
            compile_errors=[dict(code='E_TEST_CONTRACT', line=0,
                message='expect_full缺少输出：'+str(item['missing_outputs']), tc_id=item['tc_id']) for item in issues],
            failure_summary='测试契约不完整；不作为候选程序编译失败或模型错误',
            cases=[CaseResult(item['tc_id'], False, message='测试契约缺少完整输出断言') for item in issues],
            evidence_metadata=dict(judge_version=JUDGE_VERSION, test_contract_valid=False, candidate_evaluated=False, issues=issues))
    return normalized, None


def local_tests(source, problem):
    p, error = prepare(problem)
    if error is not None: return error
    result = base.local_tests(source, p)
    result.evidence_metadata.update(judge_version=JUDGE_VERSION, test_contract_valid=True)
    return result


def evaluate(source, problem, **kwargs):
    p, error = prepare(problem)
    if error is not None: return error
    result = base.evaluate(source, p, **kwargs)
    result.evidence_metadata.update(judge_version=JUDGE_VERSION, test_contract_valid=True)
    return result
