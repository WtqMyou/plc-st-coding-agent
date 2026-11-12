"""Isolated HTTP exchange; parent enforces a total deadline and stores no credentials."""
import json
import sys
from .transport import post_direct,HTTPFailure
from .providers.base import ProviderError

def main():
    try:
        job=json.load(sys.stdin)
        data=post_direct(job['url'],job['payload'],job['key'],job['timeout'])
        result=dict(ok=True,data=data)
    except HTTPFailure as error:
        result=dict(ok=False,http_status=error.status)
    except ProviderError as error:
        # post_direct supplies classifications only, never upstream bodies.
        result=dict(ok=False,error=str(error))
    except Exception:
        result=dict(ok=False,error='Upstream worker malformed result; no automatic retry')
    sys.stdout.write(json.dumps(result,ensure_ascii=False));sys.stdout.flush()
    return 0 if result['ok'] else 1

if __name__=='__main__':raise SystemExit(main())
