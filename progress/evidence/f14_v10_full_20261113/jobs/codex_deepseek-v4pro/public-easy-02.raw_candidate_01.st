FUNCTION_BLOCK FB
(* ENGINEERING_CONTRACT
- PUB001: per-cycle edge detection on all 32 bits of DWORD value.
- hasChanged: on when current value <> retained lastValue; off otherwise.
- risingBits[i]: on when lastValue[i]=0 and value[i]=1; noOfRisingBits counts bits 0..31.
- hasRisingEdges: on when noOfRisingBits > 0; off otherwise.
- fallingBits[i]: on when lastValue[i]=1 and value[i]=0; noOfFallingBits counts bits 0..31.
- hasFallingEdges: on when noOfFallingBits > 0; off otherwise.
- Retention: only lastValue is retained. Outputs are recomputed every scan; no user reset.
- First-scan baseline: lastValue=0; unspecified, tested consistently with previous value zero.
- Priority: compare against old lastValue first, then store current value at scan end.
- Bounds: counts are USINT 0..32; masks cover DWORD bits 0..31.
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
    lastValue : DWORD;
    tmp_rising : DWORD;
    tmp_falling : DWORD;
    tmp_i : INT;
END_VAR

tmp_rising := (NOT lastValue) AND value;
tmp_falling := lastValue AND (NOT value);

hasChanged := value <> lastValue;
risingBits := tmp_rising;
fallingBits := tmp_falling;

noOfRisingBits := 0;
noOfFallingBits := 0;

FOR tmp_i := 0 TO 31 DO
    IF (tmp_rising AND SHL(DWORD#1, tmp_i)) <> DWORD#0 THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF;
    IF (tmp_falling AND SHL(DWORD#1, tmp_i)) <> DWORD#0 THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF;
END_FOR;

hasRisingEdges := noOfRisingBits > 0;
hasFallingEdges := noOfFallingBits > 0;

lastValue := value;
END_FUNCTION_BLOCK