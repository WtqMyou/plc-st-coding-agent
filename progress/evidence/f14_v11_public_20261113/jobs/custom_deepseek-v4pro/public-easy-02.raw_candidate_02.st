FUNCTION_BLOCK FB
(* ENGINEERING_CONTRACT
   PUB001: every scan compares DWORD input value against stored previous value (initial 0).
   hasChanged: combinational this scan; TRUE iff current value <> stored previous value.
   hasRisingEdges/risingBits/noOfRisingBits: combinational this scan; rising mask = current AND NOT previous.
   hasFallingEdges/fallingBits/noOfFallingBits: combinational this scan; falling mask = previous AND NOT current.
   No output is latched; all edge outputs return to FALSE/0 on the next equal-value scan.
   First scan compares against default previous value 0, so edges from 0 are detected.
   Counts are USINT bit counts 0..32; masks are DWORD bit positions 0..31.
*)
(* CONTRACT_RULES [] *)
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
    lastValue : DWORD; (* defaults to 0 *)
    tmp_i : DINT;
    tmp_shift : UDINT;
    tmp_mask : DWORD;
END_VAR

hasChanged := value <> lastValue;

IF hasChanged THEN
    risingBits := value AND (NOT lastValue);
    fallingBits := lastValue AND (NOT value);
    noOfRisingBits := 0;
    noOfFallingBits := 0;

    FOR tmp_i := 0 TO 31 DO
        tmp_shift := DINT_TO_UDINT(tmp_i);
        tmp_mask := SHL(DWORD#1, tmp_shift);

        IF (risingBits AND tmp_mask) <> DWORD#0 THEN
            noOfRisingBits := noOfRisingBits + 1;
        END_IF;

        IF (fallingBits AND tmp_mask) <> DWORD#0 THEN
            noOfFallingBits := noOfFallingBits + 1;
        END_IF;
    END_FOR;

    hasRisingEdges := noOfRisingBits > 0;
    hasFallingEdges := noOfFallingBits > 0;
ELSE
    hasRisingEdges := FALSE;
    risingBits := 0;
    noOfRisingBits := 0;
    hasFallingEdges := FALSE;
    fallingBits := 0;
    noOfFallingBits := 0;
END_IF;

lastValue := value;
END_FUNCTION_BLOCK