(* ENGINEERING_CONTRACT:
 * - Inputs: value (DWORD, 32-bit), sampled every scan cycle
 * - Rising edge: prev=0 AND current=1 → risingBits = value AND NOT prevValue
 * - Falling edge: prev=1 AND current=0 → fallingBits = NOT value AND prevValue
 * - hasChanged: retention until next scan, set when value <> prevValue
 * - hasRisingEdges: combinational, true when risingBits <> 0
 * - hasFallingEdges: combinational, true when fallingBits <> 0
 * - risingBits/fallingBits: stored per-bit edge indicators, latching across scans
 * - noOfRisingBits/noOfFallingBits: USINT count of set bits in edge bitmasks
 * - Units: bit positions 0-31, counts 0-32
 * - Initialization: prevValue defaults to 0; first scan treats 0→1 as rising edges
 * - No explicit reset; state evolves per scan with prevValue update
 * - PUB001: Input value, edge detection logic, output reporting
 *)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB_DualWordEdgeDetection
VAR_INPUT
    value : DWORD;
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
    tmp_i     : USINT;
END_VAR

    // Detect rising edges: current=1 AND previous=0
    risingBits := value AND NOT prevValue;

    // Detect falling edges: previous=1 AND current=0
    fallingBits := NOT value AND prevValue;

    // Report change detection
    hasChanged := value <> prevValue;

    // Report edge occurrence flags
    hasRisingEdges := risingBits <> 0;
    hasFallingEdges := fallingBits <> 0;

    // Count rising bits (0-32)
    noOfRisingBits := 0;
    FOR tmp_i := 0 TO 31 DO
        IF (risingBits AND SHL(1, tmp_i)) <> 0 THEN
            noOfRisingBits := noOfRisingBits + 1;
        END_IF;
    END_FOR;

    // Count falling bits (0-32)
    noOfFallingBits := 0;
    FOR tmp_i := 0 TO 31 DO
        IF (fallingBits AND SHL(1, tmp_i)) <> 0 THEN
            noOfFallingBits := noOfFallingBits + 1;
        END_IF;
    END_FOR;

    // Store current value for next scan comparison
    prevValue := value;
END_FUNCTION_BLOCK