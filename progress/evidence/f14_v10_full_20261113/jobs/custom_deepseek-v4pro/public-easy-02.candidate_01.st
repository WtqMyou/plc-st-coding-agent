(*
ENGINEERING_CONTRACT
Activation: On every call after first, edge outputs computed from value vs lastValue.
Retention/hold: No latched outputs; all outputs are recomputed each scan from current and previous DWORD.
Reset/deactivation: No explicit reset; first invocation sets baseline lastValue:=value and reports no edges.
Same-scan priority: value is captured at scan start into lastValue after output computation; simultaneous change detection only.
Units/boundaries: risingBits/fallingBits are 32-bit DWORD masks, counts 0..32 as USINT; PUB001.
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
    initialized : BOOL := FALSE;
    tmp_bits : DWORD;
    tmp_count : USINT;
    tmp_i : USINT;
END_VAR

// On first call, initialize previous value and report no changes/edges.
IF NOT initialized THEN
    lastValue := value;
    initialized := TRUE;
    hasChanged := FALSE;
    hasRisingEdges := FALSE;
    risingBits := DWORD#0;
    noOfRisingBits := USINT#0;
    hasFallingEdges := FALSE;
    fallingBits := DWORD#0;
    noOfFallingBits := USINT#0;
    RETURN;
END_IF;

// Compute changes and edge masks.
hasChanged := (value <> lastValue);
risingBits := value AND (NOT lastValue);
fallingBits := lastValue AND (NOT value);
hasRisingEdges := (risingBits <> DWORD#0);
hasFallingEdges := (fallingBits <> DWORD#0);

// Count rising edge bits.
tmp_count := USINT#0;
tmp_bits := risingBits;
FOR tmp_i := USINT#0 TO USINT#31 DO
    IF (tmp_bits AND DWORD#1) <> DWORD#0 THEN
        tmp_count := tmp_count + USINT#1;
    END_IF;
    tmp_bits := SHR(tmp_bits, UINT#1);
END_FOR;
noOfRisingBits := tmp_count;

// Count falling edge bits.
tmp_count := USINT#0;
tmp_bits := fallingBits;
FOR tmp_i := USINT#0 TO USINT#31 DO
    IF (tmp_bits AND DWORD#1) <> DWORD#0 THEN
        tmp_count := tmp_count + USINT#1;
    END_IF;
    tmp_bits := SHR(tmp_bits, UINT#1);
END_FOR;
noOfFallingBits := tmp_count;

// Store current value for next cycle.
lastValue := value;

END_FUNCTION_BLOCK