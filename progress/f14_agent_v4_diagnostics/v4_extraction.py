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

SYSTEM += " Target CODESYS 3.5 ST. End IF/CASE/FOR/WHILE/REPEAT statements with semicolons. In a CODESYS DUT, the top-level END_STRUCT is directly followed by END_TYPE; do not insert a semicolon between them. Nested STRUCT field declarations keep their required separators. Use ELSIF for a flat conditional chain; preserve balanced END_IF for true nested conditionals. Declare every enum and helper variable. Do not use AT located declarations in this function block. RETURN is a bare statement; assign declared outputs before RETURN, never RETURN an expression. Preserve exact interface types including UINT, LTIME and VARIANT; do not narrow or replace them. Respect stated latching and scan behavior; do not add unstated edge-only triggers, resets or interlocks. Keep reasoning concise and emit only the implementation."
