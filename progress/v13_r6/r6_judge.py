"""Use r5 semantics unchanged, with an explicit r6 data identity."""
import r6_revision as v
import r5_judge as parent


def annotate(result):
    result.evidence_metadata.update(data_version=v.VERSION,
        execution_judge=v.JUDGE_VERSION, r6_data_only=True)
    return result


def local_tests(source, problem, *, profile=None):
    return annotate(parent.local_tests(source, problem, profile=profile))


def evaluate(source, problem, **kwargs):
    return annotate(parent.evaluate(source, problem, **kwargs))
