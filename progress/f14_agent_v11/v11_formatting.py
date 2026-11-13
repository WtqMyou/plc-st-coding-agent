"""Token-aware, semicolon-only formatting; never change types or branch structure."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent/'release'))
from stbench.st.frontend import tokenize

TERMINATORS={'END_IF','END_CASE','END_FOR','END_WHILE','END_REPEAT','END_TYPE'}

def normalize(source):
    tokens,diags=tokenize(source)
    if any(d.level=='error' for d in diags):return source,[]
    changes=[]
    for i,token in enumerate(tokens):
        # A CODESYS DUT closes its top-level STRUCT directly with END_TYPE.
        # A nested STRUCT field or another type declaration keeps its separator.
        if token.kind=='kw' and token.value.upper()=='END_STRUCT' and i+2<len(tokens) and tokens[i+1].value==';' and tokens[i+2].value.upper()=='END_TYPE':
            changes.append(dict(kind='remove_codesys_dut_struct_separator',offset=tokens[i+1].col,delete=1,text=''))
        if token.kind=='kw' and token.value.upper() in TERMINATORS and (i+1==len(tokens) or tokens[i+1].value!=';'):
            changes.append(dict(kind='insert_terminator_semicolon',offset=token.col+len(token.value),delete=0,text=';'))
    for change in sorted(changes,key=lambda c:c['offset'],reverse=True):
        pos=change['offset'];source=source[:pos]+change['text']+source[pos+change['delete']:]
    return source,changes
