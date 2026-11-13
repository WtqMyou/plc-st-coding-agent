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
    circularBuffer    : ARRAY[1..100] OF LREAL;
    bufferIndex       : INT := 1;
    sum               : LREAL := 0.0;
    sampleCount       : INT := 0;
    tmp_triggerPrev   : BOOL := FALSE;
    tmp_windowSizePrev : INT := 0;
END_VAR

(*
ENGINEERING_CONTRACT
===================
Outputs and State Retention:
| Output/State        | Activation                    | Retention                  | Reset/Deactivation       | Same-scan Priority | Units/Boundaries     |
|---------------------|-------------------------------|----------------------------|--------------------------|--------------------| ---------------------|
| average             | New value added (cyclic/trig) | Held until next update     | reset=TRUE clears to 0.0 | cyclic>trigger     | LREAL, windowSize 1-100 |
| windowSizeReached   | sampleCount >= windowSize     | Held TRUE until reset      | reset=TRUE clears FALSE  | N/A                | BOOLEAN             |
| error               | windowSize<1 OR >100          | Held TRUE until valid/reset| reset=TRUE clears FALSE  | N/A                | BOOLEAN             |
| status              | Derived from error state      | Held until state change    | reset=TRUE clears to OK  | N/A                | WORD(16#0000/16#8200) |

Behavior:
- cyclicExecution=TRUE: add value every scan cycle (PUB001)
- trigger rising edge: add one value per press (PUB002)
- cyclicExecution has priority; trigger ignored when cyclic active
- reset clears buffer, sum, count, windowSizeReached (PUB003)
- Invalid windowSize (PUB004) sets error+status and halts processing
- windowSizeReached (PUB005): FALSE until window full, TRUE thereafter
- status codes (PUB006/PUB007): 16#0000=success, 16#8200=window error

First Scan: All VAR initializes to zero/false; no spurious trigger
Boundary: windowSize bounds [1,100] inclusive; strict comparison
*)

(* CONTRACT_RULES [] *)

    // Detect windowSize change and reset buffer state
    IF windowSize <> tmp_windowSizePrev THEN
        tmp_windowSizePrev := windowSize;
        FOR i := 1 TO 100 DO
            circularBuffer[i] := 0.0;
        END_FOR;
        bufferIndex := 1;
        sampleCount := 0;
        sum := 0.0;
    END_IF;

    // Rising edge detection for trigger takes priority over cyclicExecution
    IF trigger AND NOT tmp_triggerPrev THEN
        tmp_triggerPrev := trigger;
        IF NOT reset AND windowSize >= 1 AND windowSize <= 100 THEN
            // Buffer not yet full: add new value
            IF sampleCount < windowSize THEN
                sampleCount := sampleCount + 1;
                circularBuffer[sampleCount] := value;
                sum := sum + value;
                average := sum / TO_LREAL(sampleCount);
                IF sampleCount >= windowSize THEN
                    windowSizeReached := TRUE;
                END_IF;
            ELSE
                // Buffer full: replace oldest value using circular index
                sum := sum - circularBuffer[bufferIndex];
                circularBuffer[bufferIndex] := value;
                sum := sum + value;
                bufferIndex := (bufferIndex MOD windowSize) + 1;
                average := sum / TO_LREAL(windowSize);
            END_IF;
        END_IF;
    ELSIF cyclicExecution AND NOT tmp_triggerPrev THEN
        tmp_triggerPrev := trigger;
        // cyclicExecution every scan cycle when trigger not active
        IF NOT reset AND windowSize >= 1 AND windowSize <= 100 THEN
            // Buffer not yet full: add new value
            IF sampleCount < windowSize THEN
                sampleCount := sampleCount + 1;
                circularBuffer[sampleCount] := value;
                sum := sum + value;
                average := sum / TO_LREAL(sampleCount);
                IF sampleCount >= windowSize THEN
                    windowSizeReached := TRUE;
                END_IF;
            ELSE
                // Buffer full: replace oldest value using circular index
                sum := sum - circularBuffer[bufferIndex];
                circularBuffer[bufferIndex] := value;
                sum := sum + value;
                bufferIndex := (bufferIndex MOD windowSize) + 1;
                average := sum / TO_LREAL(windowSize);
            END_IF;
        END_IF;
    ELSE
        tmp_triggerPrev := trigger;
    END_IF;

    // Reset handling - clears all state
    IF reset THEN
        bufferIndex := 1;
        sampleCount := 0;
        sum := 0.0;
        average := 0.0;
        windowSizeReached := FALSE;
        error := FALSE;
        status := 16#0000;
    ELSE
        // Validate window size when not resetting
        IF windowSize < 1 OR windowSize > 100 THEN
            error := TRUE;
            status := 16#8200;
        ELSE
            error := FALSE;
            status := 16#0000;
        END_IF;
    END_IF;

END_FUNCTION_BLOCK