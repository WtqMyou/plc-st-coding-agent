FUNCTION_BLOCK FB_DualWordEdgeDetection
VAR_INPUT
    value : DWORD;
END_VAR

VAR_OUTPUT
    hasChanged       : BOOL;
    hasRisingEdges   : BOOL;
    risingBits       : DWORD;
    noOfRisingBits   : USINT;
    hasFallingEdges  : BOOL;
    fallingBits      : DWORD;
    noOfFallingBits  : USINT;
END_VAR

VAR
    prevValue : DWORD;
END_VAR

// ENGINEERING_CONTRACT:
// Outputs: hasChanged, hasRisingEdges, hasFallingEdges, risingBits, fallingBits, noOfRisingBits, noOfFallingBits
// Retention: All outputs retain their computed values across scans until recomputed.
// Reset: No explicit reset input defined; prevValue initializes to zero on first scan.
// Edge Detection: risingBits = value & ~prevValue; fallingBits = ~value & prevValue
// Counting: Iterates all 32 bits of risingBits/fallingBits to compute USINT counts.
// hasChanged = (value <> prevValue); hasRisingEdges = (risingBits <> 0); hasFallingEdges = (fallingBits <> 0)
// PUB001: Input value is DWORD; outputs report per-scan edge events.
// CONTRACT_RULES [{"kind": "hold_until_reset", "output": "risingBits", "set_input": "value", "reset_input": null}, {"kind": "hold_until_reset", "output": "fallingBits", "set_input": "value", "reset_input": null}, {"kind": "hold_until_reset", "output": "noOfRisingBits", "set_input": "value", "reset_input": null}, {"kind": "hold_until_reset", "output": "noOfFallingBits", "set_input": "value", "reset_input": null}]

risingBits  := value AND (NOT prevValue);
fallingBits := (NOT value) AND prevValue;

hasChanged      := (value <> prevValue);
hasRisingEdges  := (risingBits <> 16#00000000);
hasFallingEdges := (fallingBits <> 16#00000000);

noOfRisingBits  := 0;
noOfFallingBits := 0;

FOR i := 0 TO 31 DO
    IF (risingBits AND SHL(16#00000001, i)) <> 16#00000000 THEN
        noOfRisingBits := noOfRisingBits + 1;
    END_IF;

    IF (fallingBits AND SHL(16#00000001, i)) <> 16#00000000 THEN
        noOfFallingBits := noOfFallingBits + 1;
    END_IF;
END_FOR;

prevValue := value;

END_FUNCTION_BLOCK