"""Token-aware, semicolon-only formatting; never change types or branch structure."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent/'release'))
from stbench.st.frontend import tokenize

TERMINATORS={'END_IF','END_CASE','END_FOR','END_WHILE','END_REPEAT','END_STRUCT','END_TYPE'}

def normalize(source):
    tokens,diags=tokenize(source)
    if any(d.level=='error' for d in diags):return source,[]
    insertions=[]
    for i,token in enumerate(tokens):
        if token.kind=='kw' and token.value.upper() in TERMINATORS and (i+1==len(tokens) or tokens[i+1].value!=';'):
            insertions.append(token.col+len(token.value))
    for pos in reversed(insertions):source=source[:pos]+';'+source[pos:]
    return source,[dict(kind='insert_terminator_semicolon',offset=pos) for pos in insertions]
