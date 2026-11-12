(*
ENGINEERING_CONTRACT
Activation: On every call including first, edge outputs computed from value versus lastValue; lastValue initializes to 0.
Retention/hold: No latched outputs; all outputs are recomputed each scan from current and previous DWORD.
Reset/deactivation: No explicit reset; first invocation compares against zero and reports rising edges for set input bits.
Same-scan priority: value is captured before output computation; lastValue is updated at the end of the same invocation.
Units/boundaries: DWORD 32-bit masks, counts 0..32 as USINT; PUB001.
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
    lastValue : DWORD := DWORD#0;
    tmp_bits : DWORD;
    tmp_count : USINT;
    tmp_i : USINT;
END_VAR

hasChanged := (value <> lastValue);
risingBits := value AND (NOT lastValue);
fallingBits := lastValue AND (NOT value);
hasRisingEdges := (risingBits <> DWORD#0);
hasFallingEdges := (fallingBits <> DWORD#0);

tmp_count := USINT#0;
tmp_bits := risingBits;
FOR tmp_i := USINT#0 TO USINT#31 DO
    IF (tmp_bits AND DWORD#1) <> DWORD#0 THEN
        tmp_count := tmp_count + USINT#1;
    END_IF;
    tmp_bits := SHR(tmp_bits, UINT#1);
END_FOR;
noOfRisingBits := tmp_count;

tmp_count := USINT#0;
tmp_bits := fallingBits;
FOR tmp_i := USINT#0 TO USINT#31 DO
    IF (tmp_bits AND DWORD#1) <> DWORD#0 THEN
        tmp_count := tmp_count + USINT#1;
    END_IF;
    tmp_bits := SHR(tmp_bits, UINT#1);
END_FOR;
noOfFallingBits := tmp_count;

lastValue := value;

END_FUNCTION_BLOCK