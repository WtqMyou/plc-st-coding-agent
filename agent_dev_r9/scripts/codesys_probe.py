# Run inside the installed CODESYS scripting engine.
from __future__ import print_function
from scriptengine import *
import io
import json
import traceback
import time
out="E:/PLC_Dev/evidence/codesys_probe.json"
d={"started_at":time.time(),"installation":"E:/PLC_Dev/platforms/CODESYS_3.5.22.40"}
try:
    p=projects.open("E:/PLC_Dev/platforms/CODESYS_3.5.22.40/CODESYS/Templates/Standard.project")
    devices=[o for o in p.get_children(recursive=True) if getattr(o,"is_device",False)]
    if len(devices)!=1:raise RuntimeError("Expected one PLC device in the standard template")
    # Identification read from the installed device.xml, not inferred from a name.
    devices[0].update(4096,"0000 0004","3.5.22.40")
    devices[0].rename("CODESYS_Control_Win_x64")
    p.project_settings.set_compilerversion_to_newest()
    for manager in [o for o in p.get_children(recursive=True) if getattr(o,"is_libman",False)]:
        for lib in list(manager.get_libraries()):
            if unicode(lib).startswith(("IoStandard,","Standard,")):
                manager.remove_library(lib)
        manager.add_library("Standard, 3.5.22.0 (System)")
        for reference in manager.references:
            if unicode(reference.name).startswith("Standard,"):
                reference.qualified_only=False
    d["objects"]=[{"name":o.get_name(),"application":getattr(o,"is_application",False),
                  "device":getattr(o,"is_device",False)} for o in p.get_children(recursive=True)]
    p.save_as("E:/PLC_Dev/builds/codesys_template.project")
    for category in system.get_message_categories():system.clear_messages(category)
    app=[o for o in p.get_children(recursive=True) if getattr(o,"is_application",False)][0]
    app.build()
    app.generate_code()
    messages=[]
    for category in system.get_message_categories():messages.extend(system.get_message_objects(category))
    d["diagnostics"]=[unicode(m) for m in messages]
    d["status"]="failed" if any(m.severity in (Severity.Error,Severity.FatalError) for m in messages) else "ok"
    d["compiler_version"]=unicode(p.project_settings.get_compilerversion())
    d["device"]={"type":4096,"id":"0000 0004","version":"3.5.22.40"}
    d["repositories"]=[{"name":r.name,"root_folder":r.root_folder} for r in librarymanager.repositories]
    p.save()
    p.close()
except Exception:
    d["error"]=traceback.format_exc()
with io.open(out,"w",encoding="utf-8") as result_file:
    result_file.write(unicode(json.dumps(d,ensure_ascii=False)))
