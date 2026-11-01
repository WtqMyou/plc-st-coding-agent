# Executed only inside CODESYS IronPython. Reuses the engine for reference audits.
from __future__ import print_function
from scriptengine import *
import io
import json
import sys
import time
import traceback

with io.open(sys.argv[1],encoding="utf-8") as source:
    manifest=json.load(source)
for item in manifest["jobs"]:
    started=time.time()
    with io.open(manifest["heartbeat"],"w",encoding="utf-8") as heartbeat:
        heartbeat.write(unicode(json.dumps({"nonce":item["nonce"],"started_at":started})))
    try:
        sys.argv=[manifest["driver"],item["path"]]
        execfile(manifest["driver"],{"__name__":"__main__"})
        with io.open(item["result"],encoding="utf-8") as result_file:
            report=json.load(result_file)
    except Exception:
        report={"nonce":item["nonce"],"status":"tool_error","diagnostics":[traceback.format_exc()]}
        if projects.primary:projects.primary.close()
    report["elapsed_s"]=time.time()-started
    with io.open(item["result"],"w",encoding="utf-8") as result_file:
        result_file.write(unicode(json.dumps(report,ensure_ascii=False)))
