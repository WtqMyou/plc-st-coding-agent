"""Isolated, local-only probe of the versioned interpreter."""
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent/'release'))
from stbench.st.typecheck import check_st
from stbench.st.interp import Interpreter,_plain_value

request=json.load(sys.stdin);parsed=check_st(request['source'])
out=dict(ok=parsed.ok,errors=[d.to_dict() for d in parsed.diags if d.level=='error'],scans=[])
if parsed.ok:
    engine=Interpreter(parsed.pou,parsed.structs)
    for inputs in request.get('scans',[]):
        for name,value in inputs.items():engine.set_var(name,value)
        engine.scan()
        out['scans'].append({name:_plain_value(engine.get_var(name)) for name in request['outputs']})
print(json.dumps(out))
