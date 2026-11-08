FUNCTION_BLOCK FB
VAR_INPUT
    enable    : BOOL;
    values    : ARRAY[1..8] OF INT;
    count     : INT;
    avgEnable : BOOL;
END_VAR

VAR_OUTPUT
    avgOut : REAL;
END_VAR

VAR
    sumVal     : DINT;
    idx        : INT;
    validCnt   : INT;
END_VAR

// Default: keep previous output (no write occurs when conditions unmet)
// Guard: enable must be TRUE, avgEnable must be TRUE
IF enable AND avgEnable THEN
    // Guard: count must be positive (prevents div-by-zero per S1)
    IF count > 0 THEN
        // Clamp to array bound per requirement 3
        validCnt := count;
        IF validCnt > 8 THEN
            validCnt := 8;
        END_IF
        
        // Sum with DINT to avoid INT overflow
        sumVal := 0;
        FOR idx := 1 TO validCnt DO
            sumVal := sumVal + values[idx];
        END_FOR
        
        // Real division; validCnt > 0 guarantees no div-by-zero
        avgOut := DINT_TO_REAL(sumVal) / DINT_TO_REAL(validCnt);
    END_IF;
END_IF;

END_FUNCTION_BLOCK