FUNCTION_BLOCK FB_MovingAverage
VAR_INPUT
    cyclicExecution : BOOL;
    trigger         : BOOL;
    value           : LREAL;
    windowSize      : INT;
    reset           : BOOL;
END_VAR

VAR_OUTPUT
    average         : LREAL;
    windowSizeReached: BOOL;
    error           : BOOL;
    status          : WORD;
END_VAR

VAR
    dataBuffer      : ARRAY[1..100] OF LREAL;
    currentIndex    : INT := 0;
    sampleCount     : INT := 0;
    sum             : LREAL := 0.0;
    lastTrigger     : BOOL := FALSE;
    lastWindowSize  : INT := 0;
END_VAR

(* =========================================================================
   ENGINEERING_CONTRACT - Moving Average Function Block
   
   PUB001: Moving arithmetic mean via FIFO sliding window
   PUB002: cyclicExecution TRUE -> auto-update every scan (no edge needed)
   PUB003: trigger rising edge -> single-sample update per edge
   PUB004: reset TRUE -> full state clear; windowSize validation 1..100
   
   OUTPUT BEHAVIOR TABLE:
   | Output            | Activation        | Retention    | Reset        | Units/Range          |
   |-------------------|-------------------|--------------|--------------|----------------------|
   | average           | on valid update   | holds last   | on reset     | LREAL, computed      |
   | windowSizeReached | when count == size| holds state  | on reset     | FALSE(0..n-1), TRUE(n)|
   | error             | windowSize !in[1,100]| holds    | on reset     | FALSE=ok, TRUE=error |
   | status            | 16#8200 on bad size| holds      | on reset     | 16#0000, 16#8200     |
   
   BOUNDARY/SAME-SCAN RULES:
   - windowSize change invalidates: reinit buffer, no error until next cycle
   - cyclicExecution dominates trigger; trigger ignored when cyclic=TRUE
   - Rising edge: lastTrigger (previous cycle) vs trigger (current)
   - Zero samples: average=0.0, windowSizeReached=FALSE
   - reset clears all state including error and status in same scan
   
   ========================================================================= *)

    // --- Reset handling (highest priority) ---
    IF reset THEN
        currentIndex     := 0;
        sampleCount      := 0;
        sum              := 0.0;
        average          := 0.0;
        windowSizeReached := FALSE;
        error            := FALSE;
        status           := 16#0000;
        lastTrigger      := FALSE;
        lastWindowSize   := 0;
        RETURN;
    END_IF

    // --- Window size validation ---
    IF (windowSize < 1) OR (windowSize > 100) THEN
        error  := TRUE;
        status := 16#8200;
        RETURN;
    END_IF

    // --- Reinitialize buffer when window size changes to valid value ---
    IF lastWindowSize <> windowSize THEN
        currentIndex     := 0;
        sampleCount      := 0;
        sum              := 0.0;
        average          := 0.0;
        windowSizeReached := FALSE;
        lastWindowSize   := windowSize;
    END_IF

    // --- Execution trigger selection ---
    // PUB002: cyclicExecution TRUE -> update every scan
    // PUB003: trigger rising edge -> update per edge
    // Same-scan priority: cyclicExecution takes precedence
    IF cyclicExecution OR (trigger AND NOT lastTrigger) THEN
        // Advance circular buffer index
        currentIndex := (currentIndex MOD windowSize) + 1;

        // Subtract the value being overwritten from sum (FIFO principle)
        IF sampleCount >= windowSize THEN
            sum := sum - dataBuffer[currentIndex];
        END_IF

        // Add new value to sum and buffer
        sum := sum + value;
        dataBuffer[currentIndex] := value;

        // Increment sample count up to window size
        IF sampleCount < windowSize THEN
            sampleCount := sampleCount + 1;
        END_IF

        // Compute moving average (sum / current count)
        average := sum / TO_LREAL(sampleCount);

        // Update window reached flag
        windowSizeReached := (sampleCount >= windowSize);

        // Clear error on successful execution
        error  := FALSE;
        status := 16#0000;
    END_IF

    // --- Latch last trigger state for edge detection ---
    lastTrigger := trigger;

END_FUNCTION_BLOCK