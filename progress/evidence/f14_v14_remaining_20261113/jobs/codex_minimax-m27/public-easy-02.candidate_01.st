FUNCTION_BLOCK FB_DualWordEdgeDetection
VAR_INPUT
    value : DWORD;
END_VAR
VAR_OUTPUT
    hasChanged     : BOOL;
    hasRisingEdges : BOOL;
    risingBits     : DWORD;
    noOfRisingBits : USINT;
    hasFallingEdges: BOOL;
    fallingBits    : DWORD;
    noOfFallingBits: USINT;
END_VAR
VAR
    prevValue : DWORD;
END_VAR

(*
ENGINEERING_CONTRACT
==================
PUB001: Edge detection per bit of DWORD input, all 32 bits tracked independently
Activation:    Continuous, outputs update every scan cycle
Retention:     prevValue retains last cycle state; risingBits/fallingBits valid for current scan only
Reset/Deact:   No explicit reset input - prevValue updates automatically each cycle
Same-scan:     Uses prevValue from previous invocation for edge calculation
Units:         BIT positions 0-31; counts are 0-32
Boundary:      32-bit DWORD; all operations use DWORD arithmetic
==================
*)

risingBits  := value AND (NOT prevValue);
fallingBits := (NOT value) AND prevValue;

hasChanged     := (value <> prevValue);
hasRisingEdges := (risingBits <> 16#0);
hasFallingEdges:= (fallingBits <> 16#0);

noOfRisingBits  := TO_USINT(SHL(value, 24) <> 16#0) + TO_USINT(SHL(value, 25) <> 16#0) +
                   TO_USINT(SHL(value, 26) <> 16#0) + TO_USINT(SHL(value, 27) <> 16#0) +
                   TO_USINT(SHL(value, 28) <> 16#0) + TO_USINT(SHL(value, 29) <> 16#0) +
                   TO_USINT(SHL(value, 30) <> 16#0) + TO_USINT(SHL(value, 31) <> 16#0);

noOfFallingBits := TO_USINT(SHL(fallingBits, 24) <> 16#0) + TO_USINT(SHL(fallingBits, 25) <> 16#0) +
                   TO_USINT(SHL(fallingBits, 26) <> 16#0) + TO_USINT(SHL(fallingBits, 27) <> 16#0) +
                   TO_USINT(SHL(fallingBits, 28) <> 16#0) + TO_USINT(SHL(fallingBits, 29) <> 16#0) +
                   TO_USINT(SHL(fallingBits, 30) <> 16#0) + TO_USINT(SHL(fallingBits, 31) <> 16#0);

prevValue := value;
END_FUNCTION_BLOCK