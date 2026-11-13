"""Keep best reporting score; choose repairs by progress and avoid reverting to stale ties."""
import re

def diagnostic_count(attempt):
    judge=attempt.get('judge',{});local=judge.get('compile_errors',[])
    structural=[e for e in local if e.get('code')=='E_FLOW_STRUCTURE']
    native=judge.get('platform_results',{}).get('codesys',{})
    lines=native.get('diagnostics',[])
    summaries=[int(m.group(1)) for line in lines if (m:=re.search(r'(\d+)\s+errors?',line,re.I))]
    return max(len(local),len(structural),max(summaries,default=0))

def select(attempts):
    candidates=[i for i,a in enumerate(attempts) if a.get('code') and not a.get('provider_error')]
    if not candidates:return None
    def score(i):
        a=attempts[i];usable=a['functional_pass'] and (a['native_pass'] or not a['native_eligible'])
        return (usable and a['verification_status'] in ('bounded_pass','not_applicable'),usable,
            a['native_pass'],a['compiles'],a['tests_passed'],-diagnostic_count(a),i)
    return max(candidates,key=score)

def memory(attempts):
    rows=[]
    for a in attempts:
        judge=a.get('judge',{});native=judge.get('platform_results',{}).get('codesys',{})
        rows.append(dict(candidate=a['idx']+1,native_pass=a['native_pass'],functional_pass=a['functional_pass'],
            passed=a['tests_passed'],total=a['tests_total'],compiler_error_count=diagnostic_count(a),
            compiler_messages=[e.get('message','') for e in judge.get('compile_errors',[])[:3]],
            native_messages=[line for line in native.get('diagnostics',[]) if re.search(r'expected|unexpected|error',line,re.I)][:3]))
    return rows
