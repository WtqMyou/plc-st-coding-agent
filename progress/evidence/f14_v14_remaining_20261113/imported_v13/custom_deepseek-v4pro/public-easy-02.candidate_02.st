(* ENGINEERING_CONTRACT
- previousValue: internal DWORD state initialized to DWORD#0; first cycle detects edges relative to 0, so every set bit is a rising edge. PUB001.
- hasChanged: activation = value <> previousValue after first scan; no retention; automatically false next scan when equal.
- hasRisingEdges/risingBits/noOfRisingBits: activation = bits transition 0->1 from previousValue to value; no retention; counts 0..32.
- hasFallingEdges/fallingBits/noOfFallingBits: activation = bits transition 1->0; no retention; counts 0..32.
- Same-scan: rising and falling may both be true for different bit positions; hasChanged is true if either set.
- Units/boundaries: 32-bit DWORD masks, USINT counts range 0..32; detection each scan after first. PUB001.
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
    previousValue : DWORD;
    tmp_changed : DWORD;
    tmp_rising : DWORD;
    tmp_falling : DWORD;
    tmp_i : UDINT;
    tmp_count : USINT;
END_VAR


tmp_changed := value XOR previousValue;
tmp_rising := value AND (NOT previousValue);
tmp_falling := previousValue AND (NOT value);

hasChanged := tmp_changed <> DWORD#0;
hasRisingEdges := tmp_rising <> DWORD#0;
hasFallingEdges := tmp_falling <> DWORD#0;

risingBits := tmp_rising;
fallingBits := tmp_falling;

tmp_count := 0;
FOR tmp_i := 0 TO 31 DO
    IF (risingBits AND SHL(DWORD#1, tmp_i)) <> DWORD#0 THEN
        tmp_count := tmp_count + 1;
    END_IF;
END_FOR;
noOfRisingBits := tmp_count;

tmp_count := 0;
FOR tmp_i := 0 TO 31 DO
    IF (fallingBits AND SHL(DWORD#1, tmp_i)) <> DWORD#0 THEN
        tmp_count := tmp_count + 1;
    END_IF;
END_FOR;
noOfFallingBits := tmp_count;

previousValue := value;
END_FUNCTION_BLOCK