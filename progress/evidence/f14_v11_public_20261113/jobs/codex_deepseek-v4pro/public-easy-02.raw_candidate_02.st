(* ENGINEERING_CONTRACT
   hasChanged: activation when current DWORD differs from stored previous scan; combinational, not held.
   hasRisingEdges/risingBits/noOfRisingBits: activation for 0->1 bits versus prior scan; computed each scan, not held.
   hasFallingEdges/fallingBits/noOfFallingBits: activation for 1->0 bits versus prior scan; computed each scan, not held.
   Retention/hold: only prevValue is retained; outputs are overwritten every scan from current comparison.
   Explicit reset/deactivation: none defined in PUB001; first scan establishes baseline with no edge/changed outputs.
   Same-scan priority: current value is compared against retained prior word before prior word is updated.
   Units/boundaries: DWORD bits 0..31, USINT counts 0..32, zero-based bit iteration.
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
    prevValue : DWORD;
    isInitialized : BOOL;
    tmpRising : DWORD;
    tmpFalling : DWORD;
    tmpBitIndex : INT;
END_VAR

IF NOT isInitialized THEN
    hasChanged := FALSE;
    hasRisingEdges := FALSE;
    risingBits := DWORD#0;
    noOfRisingBits := 0;
    hasFallingEdges := FALSE;
    fallingBits := DWORD#0;
    noOfFallingBits := 0;
    prevValue := value;
    isInitialized := TRUE;
    RETURN;
END_IF;

hasChanged := value <> prevValue;
tmpRising := value AND (NOT prevValue);
tmpFalling := prevValue AND (NOT value);

risingBits := tmpRising;
fallingBits := tmpFalling;
hasRisingEdges := tmpRising <> DWORD#0;
hasFallingEdges := tmpFalling <> DWORD#0;

noOfRisingBits := 0;
noOfFallingBits := 0;

FOR tmpBitIndex := 0 TO 31 DO
    IF (tmpRising AND SHL(DWORD#1, TO_DINT(tmpBitIndex))) <> DWORD#0 THEN
        noOfRisingBits := TO_USINT(noOfRisingBits + 1);
    END_IF;
    IF (tmpFalling AND SHL(DWORD#1, TO_DINT(tmpBitIndex))) <> DWORD#0 THEN
        noOfFallingBits := TO_USINT(noOfFallingBits + 1);
    END_IF;
END_FOR;

prevValue := value;

END_FUNCTION_BLOCK