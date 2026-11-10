"""No new execution semantics: bind r7 evaluation to the returned data contracts."""
import r8_revision as v
import r7_judge as parent


def annotate(result):
    result.evidence_metadata.update(data_version=v.VERSION,functional_data_version=v.VERSION,
        spec_revision=v.VERSION,execution_judge=v.JUDGE_VERSION)
    return result


def local_tests(source,problem,*,profile=None):
    return annotate(parent.local_tests(source,problem,profile=profile))


def evaluate(source,problem,**kwargs):
    return annotate(parent.evaluate(source,problem,**kwargs))
