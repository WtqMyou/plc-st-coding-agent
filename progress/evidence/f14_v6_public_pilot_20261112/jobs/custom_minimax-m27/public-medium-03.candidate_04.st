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
    dataBuffer         : ARRAY[1..100] OF LREAL;
    currentIndex       : INT := 0;
    sampleCount        : INT := 0;
    sum                : LREAL := 0.0;
    tmp_lastTrigger    : BOOL := FALSE;
    tmp_newSample      : BOOL := FALSE;
    tmp_effectiveWin   : INT := 0;
    tmp_winSizeChanged : BOOL := FALSE;
    tmp_prevWinSize    : INT := 0;
    tmp_startIdx       : INT := 0;
    tmp_i              : INT := 0;
    tmp_newSum         : LREAL := 0.0;
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
- windowSize change → prune buffer to contain only most recent windowSize samples

Same-Scan Priority:
1. reset check (highest)
2. windowSize validation (set error=TRUE if invalid, return)
3. windowSize change detection → prune buffer
4. trigger rising-edge detection
5. cyclicExecution evaluation
6. sample insertion / buffer rotation
7. average recalculation

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
        tmp_winSizeChanged := FALSE;
        tmp_prevWinSize   := 0;
        tmp_startIdx      := 0;
        tmp_i             := 0;
        tmp_newSum        := 0.0;
        RETURN;
    END_IF;

    // Clamp effective window to array upper bound for validation
    tmp_effectiveWin := windowSize;
    IF tmp_effectiveWin > 100 THEN
        tmp_effectiveWin := 100;
    END_IF;

    // Validate window size (PUB007)
    // Only clear error AFTER validation passes, so invalid sizes preserve error state
    IF windowSize < 1 OR windowSize > 100 THEN
        error  := TRUE;
        status := 16#8200;
        RETURN;
    END_IF;

    // Valid windowSize: clear error and set success status (PUB006)
    error  := FALSE;
    status := 16#0000;

    // Detect windowSize change and prune buffer if needed
    tmp_winSizeChanged := (tmp_prevWinSize <> 0) AND (tmp_prevWinSize <> windowSize);
    IF tmp_winSizeChanged AND sampleCount > 0 THEN
        // Prune buffer to contain only most recent windowSize samples
        tmp_effectiveWin := windowSize;
        IF tmp_effectiveWin > 100 THEN
            tmp_effectiveWin := 100;
        END_IF;

        IF sampleCount > tmp_effectiveWin THEN
            // Calculate start index for circular buffer (oldest sample to keep)
            // Most recent samples are at positions (currentIndex - k + 1) through currentIndex
            tmp_startIdx := ((currentIndex - tmp_effectiveWin) MOD 100) + 1;
            IF tmp_startIdx < 1 THEN
                tmp_startIdx := tmp_startIdx + 100;
            END_IF;

            // Copy most recent samples to front of buffer and recalculate sum
            tmp_newSum := 0.0;
            FOR tmp_i := 1 TO tmp_effectiveWin DO
                dataBuffer[tmp_i] := dataBuffer[tmp_startIdx + tmp_i - 1];
                tmp_newSum := tmp_newSum + dataBuffer[tmp_i];
            END_FOR;

            // Clear remaining buffer slots
            FOR tmp_i := tmp_effectiveWin + 1 TO 100 DO
                dataBuffer[tmp_i] := 0.0;
            END_FOR;

            sampleCount := tmp_effectiveWin;
            sum := tmp_newSum;
            currentIndex := tmp_effectiveWin;
        END_IF;
    END_IF;

    // Track current windowSize for next-cycle change detection
    tmp_prevWinSize := windowSize;

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
        tmp_effectiveWin := windowSize;
        IF tmp_effectiveWin > 100 THEN
            tmp_effectiveWin := 100;
        END_IF;

        IF sampleCount < tmp_effectiveWin THEN
            // Buffer not yet full: append new value
            sampleCount := sampleCount + 1;
            currentIndex := sampleCount;
            dataBuffer[currentIndex] := value;
            sum := sum + value;
        ELSE
            // Buffer full: rotate out oldest value using circular buffer
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