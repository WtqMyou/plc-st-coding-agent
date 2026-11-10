"""Minimal isolated HTTP exchange; never logs request credentials."""
import json
import sys
from full_r8b_transport import exchange,HTTPFailure
from stbench.providers.base import ProviderError

def main():
    try:
        job=json.load(sys.stdin)
        data=exchange(job['url'],job['payload'],job['key'],job['timeout'],job['directory'])
        result=dict(ok=True,data=data)
    except HTTPFailure as exc:result=dict(ok=False,http_status=exc.status)
    except ProviderError as exc:result=dict(ok=False,error=str(exc),exception_type=type(exc).__name__)
    except Exception as exc:result=dict(ok=False,error='HTTP worker '+type(exc).__name__+'; no automatic retry',exception_type=type(exc).__name__)
    sys.stdout.write(json.dumps(result,ensure_ascii=False));sys.stdout.flush()
    return 0 if result['ok'] else 1

if __name__=='__main__':raise SystemExit(main())
