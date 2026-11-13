# Executed by CODESYS IronPython, not system Python. Keep Python 2.7 compatible.
from __future__ import print_function
from scriptengine import *
import io
import json
import sys
import os
import re
import traceback

job=json.loads(io.open(sys.argv[1],encoding="utf-8").read())
report={"nonce":job["nonce"],"status":"tool_error","diagnostics":[]}
try:
    project=projects.open(job["template"])
    project.save_as(job["project"])
    apps=[o for o in project.get_children(recursive=True) if getattr(o,"is_application",False)]
    if len(apps)!=1:
        raise RuntimeError("Template must have exactly one Application")
    app=apps[0]
    for text in job["types"]:
        match=re.search(r"\bTYPE\s+([A-Za-z_][A-Za-z0-9_]*)",text,re.I)
        if match is None:
            raise RuntimeError("Missing declared DUT type name")
        name=match.group(1)
        dut=app.create_dut(name)
        dut.textual_declaration.replace(text)
    if job["kind"]=="FUNCTION_BLOCK":
        pou=app.create_function_block(job["name"])
    elif job["kind"]=="PROGRAM":
        pou=app.create_program(job["name"])
    else:
        return_type=job["declaration"].splitlines()[0].split(":",1)[1].strip()
        pou=app.create_function(job["name"],return_type)
    pou.textual_declaration.replace(job["declaration"])
    pou.textual_implementation.replace(job["implementation"])
    # Force checking and code generation even if the POU is not called by PLC_PRG.
    pou.build_properties.link_always=True
    for category in system.get_message_categories():
        system.clear_messages(category)
    app.build()
    app.generate_code()
    messages=[]
    for category in system.get_message_categories():
        messages.extend(system.get_message_objects(category))
    if not any(m.severity in (Severity.Error,Severity.FatalError) for m in messages):
        boot_path=os.path.splitext(job["project"])[0]+".app"
        app.create_boot_application(boot_path,True)
        if not os.path.isfile(boot_path):raise RuntimeError("Offline boot application was not created")
        report["boot_application"]=boot_path
        messages=[]
        for category in system.get_message_categories():messages.extend(system.get_message_objects(category))
    report["diagnostics"]=[unicode(m) for m in messages]
    report["status"]="failed" if any(m.severity in (Severity.Error,Severity.FatalError) for m in messages) else "passed"
    project.save()
except Exception:
    report["diagnostics"].append(traceback.format_exc())
finally:
    with io.open(job["result"],"w",encoding="utf-8") as result_file:
        result_file.write(unicode(json.dumps(report,ensure_ascii=False)))
    if projects.primary:
        projects.primary.close()
