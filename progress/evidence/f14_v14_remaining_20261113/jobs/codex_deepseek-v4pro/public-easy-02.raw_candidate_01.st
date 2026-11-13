(*
ENGINEERING_CONTRACT
- Scope: PUB001, DWORD edge detection reported every scan.
- hasChanged: combinational; TRUE when current value differs from previous scan.
- risingBits/fallingBits: current-scan edge masks, recomputed every call; no retention.
- hasRisingEdges/hasFallingEdges: combinational nonzero-mask indicators.
- noOfRisingBits/noOfFallingBits: USINT popcount, 0..32, unit = edge count.
- State update: previous value stored after outputs are evaluated.
- First-scan baseline: unspecified; implemented as zero-initialized previous value.
- Same-scan priority: edges are functions of the current value and the prior value.
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR_INPUT
    value : DWORD;
END_VAR
VAR_OUTPUT
    hasChanged : BOOL;
    hasRisingEdges : BOOL;
    risingBits : DWORD;
    noOfRisingBits : USINT;
    hasFallingEdges : BOOL;
    fallingBits : DWORD;
    noOfFallingBits : USINT;
END_VAR
VAR
    local_lastValue : DWORD := DWORD#0;
    tmp_bitIndex : INT;
    tmp_bitMask : DWORD;
END_VAR

hasChanged := value <> local_lastValue;
risingBits := (NOT local_lastValue) AND value;
fallingBits := local_lastValue AND (NOT value);

hasRisingEdges := risingBits <> DWORD#0;
hasFallingEdges := fallingBits <> DWORD#0;

noOfRisingBits := 0;
noOfFallingBits := 0;

FOR tmp_bitIndex := 0 TO 31 DO
    tmp_bitMask := SHL(DWORD#1, tmp_bitIndex);
    IF (risingBits AND tmp_bitMask) <> DWORD#0 THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF;
    IF (fallingBits AND tmp_bitMask) <> DWORD#0 THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF;
END_FOR;

local_lastValue := value;
END_FUNCTION_BLOCK