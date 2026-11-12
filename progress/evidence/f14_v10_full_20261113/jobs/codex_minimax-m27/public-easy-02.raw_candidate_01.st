FUNCTION_BLOCK FB_DualWordEdgeDetector
VAR_INPUT
END_VAR
VAR_OUTPUT
    hasChanged     : BOOL  := FALSE;
    hasRisingEdges : BOOL  := FALSE;
    risingBits     : DWORD := 0;
    noOfRisingBits : USINT := 0;
    hasFallingEdges: BOOL  := FALSE;
    fallingBits    : DWORD := 0;
    noOfFallingBits: USINT := 0;
END_VAR
VAR
    previousValue : DWORD := 0;
    tmpXorMask    : DWORD;
    tmpRising     : DWORD;
    tmpFalling    : DWORD;
    tmpIdx        : USINT;
END_VAR
VAR_TEMP
END_VAR
(*
ENGINEERING_CONTRACT
===================
PUB001: Dual-word edge detection every scan cycle
-----------------------------------------------
Output/State    | Activation           | Retention    | Reset        | Priority     | Units/Boundary
----------------|----------------------|--------------|--------------|--------------|-----------------
hasChanged      | value <> prev        | per scan     | auto-clear   | same-scan    | BOOL
risingBits      | cur=1 AND prev=0     | per scan     | auto-clear   | same-scan    | DWORD mask
noOfRisingBits  | count(risingBits)    | per scan     | auto-clear   | same-scan    | 0..32
hasFallingEdges | fallingBits <> 0     | per scan     | auto-clear   | same-scan    | BOOL
fallingBits     | cur=0 AND prev=1     | per scan     | auto-clear   | same-scan    | DWORD mask
noOfFallingBits | count(fallingBits)   | per scan     | auto-clear   | same-scan    | 0..32
previousValue   | hold across scans    | retained     | no reset     | same-scan    | DWORD

Same-scan behavior: All outputs derived from (value, previousValue) on each invocation.
No edge-only triggers or external resets are specified.
*)
tmpXorMask := value XOR previousValue;
tmpRising  := tmpXorMask AND value;
tmpFalling := tmpXorMask AND previousValue;

hasChanged      := (value <> previousValue);
hasRisingEdges  := (tmpRising <> 0);
hasFallingEdges := (tmpFalling <> 0);
risingBits      := tmpRising;
fallingBits     := tmpFalling;

noOfRisingBits  := 0;
noOfFallingBits := 0;
FOR tmpIdx := 0 TO 31 DO
    IF (SHR(risingBits, TO_UINT(tmpIdx)) AND 1) = 1 THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF
    IF (SHR(fallingBits, TO_UINT(tmpIdx)) AND 1) = 1 THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF
END_FOR

previousValue := value;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)