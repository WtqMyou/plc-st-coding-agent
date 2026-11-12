FUNCTION_BLOCK FB_DualWordEdgeDetection
VAR_INPUT
END_VAR
VAR_OUTPUT
    hasChanged      : BOOL;
    hasRisingEdges  : BOOL;
    risingBits      : DWORD;
    noOfRisingBits  : USINT;
    hasFallingEdges : BOOL;
    fallingBits     : DWORD;
    noOfFallingBits : USINT;
END_VAR
VAR
    prevValue : DWORD;
END_VAR
VAR_TEMP
    tmp_i         : USINT;
    tmp_rising    : DWORD;
    tmp_falling   : DWORD;
END_VAR
// ENGINEERING_CONTRACT
// +-----------+------------+-----------+-----------+--------+----------------+----------+
// | Output    | Activation | Retention | Reset     | SameScan| Units/Bounds   |
// +-----------+------------+-----------+-----------+--------+----------------+----------+
// |hasChanged     | value<>prevValue | no | implicit per cycle | yes | BOOLEAN      |
// |hasRisingEdges | risingBits<>0    | no | implicit per cycle | yes | BOOLEAN      |
// |risingBits     | rising edge calc | no | implicit per cycle | yes | DWORD        |
// |noOfRisingBits | bit count        | no | implicit per cycle | yes | 0..32        |
// |hasFallingEdges| fallingBits<>0   | no | implicit per cycle | yes | BOOLEAN      |
// |fallingBits    | falling edge calc| no | implicit per cycle | yes | DWORD        |
// |noOfFallingBits| bit count        | no | implicit per cycle | yes | 0..32        |
// +-------------------------------------------------------------------------------+
// PUB001: Rising edge = (current=1 AND prev=0). Falling edge = (current=0 AND prev=1).
// PUB002: Bit counts use iterative population count across all 32 bits.
// PUB003: State retention only for prevValue (internal). No public output latches.
// (* CONTRACT_RULES [] *)
// +-------------------------------------------------------------------------------+

tmp_rising  := value AND (NOT prevValue);   // 0->1 transition
tmp_falling := (NOT value) AND prevValue;   // 1->0 transition

risingBits      := tmp_rising;
hasRisingEdges  := (tmp_rising <> 0);
fallingBits     := tmp_falling;
hasFallingEdges := (tmp_falling <> 0);

noOfRisingBits  := 0;
noOfFallingBits := 0;
FOR tmp_i := 0 TO 31 DO
    IF (SHR(tmp_rising, tmp_i) AND 1) = 1 THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF;
    IF (SHR(tmp_falling, tmp_i) AND 1) = 1 THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF;
END_FOR;

hasChanged := (value <> prevValue);

prevValue := value;

END_FUNCTION_BLOCK