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

SYSTEM='''Return only one complete, self-contained IEC 61131-3 Structured Text FUNCTION_BLOCK implementation, including all VAR sections and END_FUNCTION_BLOCK. Use the exact input/output/inout names, types, directions and behavior in the user task. Use FUNCTION_BLOCK (not PROGRAM) for every task in this benchmark. Necessary named TYPE definitions may precede the block. Keep helper state inside VAR; do not emit nested FUNCTION/METHOD/ACTION or workspace-inspection commentary. Use supported standard ST constructs and explicit type conversions. Avoid CODESYS reserved local identifiers s and r; use SHL/SHR functions for shifts. Return a single fenced st block, without explanatory prose outside ST comments. Do not inspect files or request tools. The user task remains verbatim; these are shared packaging/output requirements for both frameworks.'''

SYSTEM += " Target CODESYS 3.5 ST. End IF/CASE/FOR/WHILE/REPEAT statements with semicolons. In a CODESYS DUT, the top-level END_STRUCT is directly followed by END_TYPE; do not insert a semicolon between them. Nested STRUCT field declarations keep their required separators. Use ELSIF for a flat conditional chain; preserve balanced END_IF for true nested conditionals. Declare every enum and helper variable. Do not use AT located declarations in this function block. RETURN is a bare statement; assign declared outputs before RETURN, never RETURN an expression. Preserve exact interface types including UINT, LTIME and VARIANT; do not narrow or replace them. Respect stated latching and scan behavior; do not add unstated edge-only triggers, resets or interlocks. Keep reasoning concise and emit only the implementation."

from v12_contracts import DESIGN_INSTRUCTION, CAPABILITIES
SYSTEM += "\n" + DESIGN_INSTRUCTION + "\n" + CAPABILITIES

SYSTEM += " CODESYS function-block statements start directly after declaration sections; never emit Pascal BEGIN or bare END wrappers. Before output, balance every IF/END_IF, CASE/END_CASE, FOR/END_FOR, WHILE/END_WHILE and REPEAT/END_REPEAT across all branches. State-machine transitions and output retention are separate decisions: derive each output write condition from public requirements. If a step starts an output, only a stated stop/reset condition may cancel its retained value; do not infer shutdown merely because another step starts. Distinguish pulses, combinational commands, and stored process values in the engineering contract. For each stored numeric output, state which event updates it and preserve it otherwise. When a new target is already reached, evaluate the final same-scan outputs using current public sensor values. Keep implementation and comments concise, especially during repairs."

from v12_repairs import PUBLIC_EXECUTION_CONTRACT
SYSTEM += "\n" + PUBLIC_EXECUTION_CONTRACT
