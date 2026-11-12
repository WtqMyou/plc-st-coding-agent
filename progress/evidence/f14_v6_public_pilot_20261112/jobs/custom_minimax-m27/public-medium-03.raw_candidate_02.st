FUNCTION_BLOCK FB_MovingAverage
VAR_INPUT
    cyclicExecution : BOOL;
    trigger         : BOOL;
    value           : LREAL;
    windowSize      : INT;
    reset           : BOOL;
END_VAR

VAR_OUTPUT
    average           : LREAL;
    windowSizeReached : BOOL;
    error             : BOOL;
    status            : WORD;
END_VAR

VAR
    dataBuffer       : ARRAY[1..100] OF LREAL;
    currentIndex     : INT := 0;
    sampleCount      : INT := 0;
    sum              : LREAL := 0.0;
    tmp_lastTrigger  : BOOL := FALSE;
    tmp_newSample    : BOOL := FALSE;
    tmp_effectiveWin : INT := 0;
END_VAR

(*
ENGINEERING_CONTRACT
===================
Operation Modes:
- cyclicExecution=TRUE: Update every scan cycle; trigger ignored (PUB002)
- cyclicExecution=FALSE: Rising edge on trigger updates average (PUB003)
- reset=TRUE: Clear all state, outputs to default, status=SUCCESS (PUB004)

Output Retention Policy:
| Output             | Activation         | Retention    | Reset by reset=TRUE |
|--------------------|--------------------|--------------|---------------------|
| average            | Each valid sample  | Hold last    | Yes (→0.0)          |
| windowSizeReached  | sampleCount>=winSz | Hold TRUE    | Yes (→FALSE)        |
| error              | windowSize<1 or >100| Hold TRUE   | Yes (→FALSE)        |
| status             | Per validation     | Hold code    | Yes (→SUCCESS)      |

Boundary Conditions:
- windowSize<1 OR >100 → error=TRUE, status=16#8200, skip processing (PUB004, PUB007)
- reset asserted → immediate clear, no processing (PUB004)
- Empty window (sampleCount=0) → average=0.0 (division-safe)
- Circular buffer wraps at windowSize, never exceeds 100 elements

Same-Scan Priority:
1. reset check (highest)
2. windowSize validation
3. trigger rising-edge detection
4. cyclicExecution evaluation
5. sample insertion / buffer rotation
6. average recalculation

Units: LREAL for all arithmetic (PUB001). windowSize in slots [1..100].
*)

(* CONTRACT_RULES
[
  {"kind": "hold_until_reset", "output": "windowSizeReached", "set_input": null, "reset_input": "reset"},
  {"kind": "hold_until_reset", "output": "error", "set_input": null, "reset_input": "reset"},
  {"kind": "hold_until_reset", "output": "status", "set_input": null, "reset_input": "reset"}
]
*)

    // Reset: clear all state and outputs
    IF reset THEN
        currentIndex      := 0;
        sampleCount       := 0;
        sum               := 0.0;
        average           := 0.0;
        windowSizeReached := FALSE;
        error             := FALSE;
        status            := 16#0000;
        tmp_lastTrigger   := FALSE;
        tmp_newSample     := FALSE;
        tmp_effectiveWin  := 0;
        RETURN;
    END_IF;

    // Validate window size (PUB007)
    IF windowSize < 1 OR windowSize > 100 THEN
        error  := TRUE;
        status := 16#8200;
        RETURN;
    END_IF;

    // No validation error; set success status (PUB006)
    error  := FALSE;
    status := 16#0000;

    // Determine if a new sample should be processed (PUB002, PUB003)
    tmp_newSample := FALSE;
    IF cyclicExecution THEN
        tmp_newSample := TRUE;
    ELSIF trigger AND NOT tmp_lastTrigger THEN
        tmp_newSample := TRUE;
    END_IF;
    tmp_lastTrigger := trigger;

    // Process new data point if triggered (PUB001)
    IF tmp_newSample THEN
        // Clamp effective window to array upper bound (100)
        tmp_effectiveWin := windowSize;
        IF tmp_effectiveWin > 100 THEN
            tmp_effectiveWin := 100;
        END_IF;

        IF sampleCount < tmp_effectiveWin THEN
            // Window not yet full: append new value
            sampleCount := sampleCount + 1;
            dataBuffer[sampleCount] := value;
            sum := sum + value;
        ELSE
            // Window full: rotate out oldest value using circular buffer
            currentIndex := (currentIndex MOD tmp_effectiveWin) + 1;
            sum := sum - dataBuffer[currentIndex] + value;
            dataBuffer[currentIndex] := value;
        END_IF;
    END_IF;

    // Calculate moving arithmetic mean (PUB001)
    IF sampleCount > 0 THEN
        average := sum / TO_LREAL(sampleCount);
    ELSE
        average := 0.0;
    END_IF;

    // Indicate whether maximum window width has been reached (PUB001)
    tmp_effectiveWin := windowSize;
    IF tmp_effectiveWin > 100 THEN
        tmp_effectiveWin := 100;
    END_IF;
    windowSizeReached := (sampleCount >= tmp_effectiveWin);

END_FUNCTION_BLOCK