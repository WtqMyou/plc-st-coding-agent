(* ENGINEERING_CONTRACT
   average: recomputed each scan for active stored samples; 0.0 when no samples or after reset. Units follow value.
   windowSizeReached: TRUE iff stored valid sample count >= current valid windowSize; cleared by reset and on invalid window.
   error/status: enabled by windowSize outside 1..100; status 16#8200, otherwise 16#0000 (PUB004/PUB006/PUB007).
   same-scan priority: level-true reset first, then window validation, then cyclic or rising-edge sample; cyclic TRUE ignores trigger edge (PUB002/PUB003).
   reset: explicit level-true clear of stored samples, count, average, and reached state; no same-scan sample after reset.
   trigger: internal rising-edge detector; each valid, non-reset rising edge adds one value.
   retention: valid stored samples persist without reset; dynamic window resizing uses the newest min(validCount, windowSize) samples.
   boundaries: windowSize [1,100], storage capacity 100; average is LREAL mean with no unit conversion.
*)
FUNCTION_BLOCK FB
VAR_INPUT
    cyclicExecution : BOOL;
    trigger : BOOL;
    value : LREAL;
    windowSize : INT;
    reset : BOOL;
END_VAR
VAR_OUTPUT
    average : LREAL;
    windowSizeReached : BOOL;
    error : BOOL;
    status : WORD;
END_VAR
VAR
    buffer : ARRAY[0..99] OF LREAL;
    nextIndex : INT := 0;
    validCount : INT := 0;
    triggerPrevious : BOOL;
    triggerRising : BOOL;
    activeWindow : INT;
    startIndex : INT;
    loopIndex : INT;
    sumValue : LREAL;
END_VAR

triggerRising := trigger AND NOT triggerPrevious;
triggerPrevious := trigger;

IF reset THEN
    validCount := 0;
    nextIndex := 0;
    average := 0.0;
    windowSizeReached := FALSE;
END_IF;

IF (windowSize < 1) OR (windowSize > 100) THEN
    error := TRUE;
    status := 16#8200;
    average := 0.0;
    windowSizeReached := FALSE;
ELSE
    error := FALSE;
    status := 16#0000;

    IF NOT reset THEN
        IF cyclicExecution OR triggerRising THEN
            buffer[nextIndex] := value;
            nextIndex := nextIndex + 1;

            IF nextIndex > 99 THEN
                nextIndex := 0;
            END_IF;

            IF validCount < 100 THEN
                validCount := validCount + 1;
            END_IF;
        END_IF;
    END_IF;

    activeWindow := windowSize;
    IF activeWindow > validCount THEN
        activeWindow := validCount;
    END_IF;

    IF activeWindow > 0 THEN
        sumValue := 0.0;
        FOR loopIndex := 0 TO activeWindow - 1 DO
            startIndex := nextIndex - 1 - loopIndex;
            IF startIndex < 0 THEN
                startIndex := startIndex + 100;
            END_IF;
            sumValue := sumValue + buffer[startIndex];
        END_FOR;
        average := sumValue / INT_TO_LREAL(activeWindow);
    ELSE
        average := 0.0;
    END_IF;

    windowSizeReached := validCount >= windowSize;
END_IF;
END_FUNCTION_BLOCK