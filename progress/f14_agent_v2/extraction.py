"""Strip presentation fences only; never complete or rewrite model ST semantics."""
import re
FENCES=re.compile(r'^\s*```([^\r\n`]*)\r?\n(.*?)^\s*```\s*$',re.M|re.S)
ALIASES={'','st','iec','iecst','iec61131','iec61131-3','structuredtext','pascal','pou','text','plc'}
def extract_code(text):
    blocks=FENCES.findall(text)
    if not blocks:return text.strip()
    def score(pair):
        language,body=pair;normalized=re.sub(r'[\s_-]+','',language.casefold())
        return (normalized in ALIASES,bool(re.search(r'\bFUNCTION_BLOCK\b',body,re.I)),len(body))
    return max(blocks,key=score)[1].strip()

SYSTEM='''Return only one complete, self-contained IEC 61131-3 Structured Text FUNCTION_BLOCK implementation, including all VAR sections and END_FUNCTION_BLOCK. Use the exact input/output/inout names, types, directions and behavior in the user task. Use FUNCTION_BLOCK (not PROGRAM) for every task in this benchmark. Necessary named TYPE definitions may precede the block. Keep helper state inside VAR; do not emit nested FUNCTION/METHOD/ACTION or workspace-inspection commentary. Use supported standard ST constructs and explicit type conversions. Avoid CODESYS reserved local identifiers s and r; use SHL/SHR functions for shifts. Return a single fenced st block, without explanatory prose. Do not inspect files or request tools. The user task remains verbatim; these are shared packaging/output requirements for both frameworks.'''
