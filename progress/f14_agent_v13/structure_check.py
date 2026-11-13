"""Candidate-only IEC block structure diagnostics; no task answers or tests."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent/'release'))
from stbench.st.frontend import tokenize

OPEN={'IF':'END_IF','CASE':'END_CASE','FOR':'END_FOR','WHILE':'END_WHILE','REPEAT':'END_REPEAT'}

def check(source):
    tokens,lexical=tokenize(source)
    if any(d.level=='error' for d in lexical):return []
    starts=[i for i,t in enumerate(tokens) if t.value.upper()=='FUNCTION_BLOCK' and t.kind!='str']
    if not starts:return []
    start=starts[0]+2;decl=False;stack=[];errors=[]
    for t in tokens[start:]:
        if t.kind in ('str','eof'):continue
        value=t.value.upper()
        if value in ('VAR','VAR_INPUT','VAR_OUTPUT','VAR_IN_OUT','VAR_TEMP','VAR_EXTERNAL','VAR_GLOBAL'):
            decl=True;continue
        if value=='END_VAR':decl=False;continue
        if decl:continue
        def add(message):errors.append(dict(code='E_FLOW_STRUCTURE',line=t.line,message=message))
        if value in ('BEGIN','END'):
            add('Pascal wrapper '+value+' is not part of a CODESYS ST function-block body. Start statements immediately after END_VAR; terminate the POU with END_FUNCTION_BLOCK.')
        elif value in OPEN:stack.append((value,t.line))
        elif value in OPEN.values():
            if not stack:add('Unmatched '+value+'; no corresponding opening statement.')
            elif OPEN[stack[-1][0]]!=value:
                add('Expected '+OPEN[stack[-1][0]]+' for '+stack[-1][0]+' at line '+str(stack[-1][1])+', found '+value+'. Repair nesting; do not add unrelated terminators.')
                # Resynchronize only diagnostics, never change the program.
                match=next((i for i in range(len(stack)-1,-1,-1) if OPEN[stack[i][0]]==value),None)
                if match is not None:stack=stack[:match]
            else:stack.pop()
        elif value=='ELSIF' and (not stack or stack[-1][0]!='IF'):add('ELSIF requires an open IF at this nesting level.')
        elif value=='ELSE' and (not stack or stack[-1][0] not in ('IF','CASE')):add('ELSE requires an open IF or CASE at this nesting level.')
        elif value=='END_FUNCTION_BLOCK':break
    for value,line in reversed(stack):errors.append(dict(code='E_FLOW_STRUCTURE',line=line,message='Unclosed '+value+' opened here; requires '+OPEN[value]+' before ending its enclosing block.'))
    return errors[:12]

def context(source,diagnostics):
    lines=source.splitlines();selected=set()
    for diagnostic in diagnostics[:6]:
        line=diagnostic.get('line',0)
        selected.update(range(max(1,line-1),min(len(lines),line+2)+1))
    return '\n'.join(str(i)+': '+lines[i-1] for i in sorted(selected))
