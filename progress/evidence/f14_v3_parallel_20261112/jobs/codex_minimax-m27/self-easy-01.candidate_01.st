FUNCTION_BLOCK FB
VAR
    prevAvgOut : REAL := 0.0;
END_VAR
VAR_INPUT
    enable     : BOOL;
    values     : ARRAY[1..8] OF INT;
    count      : INT;
    avgEnable  : BOOL;
END_VAR
VAR_OUTPUT
    avgOut : REAL;
END_VAR
VAR_TEMP
    sum : DINT;
    effectiveCount : INT;
END_VAR

    // Calculate only when enabled, averaging is active, and we have valid samples
    IF enable AND avgEnable AND count > 0 THEN
        // Clamp count to valid array bounds
        IF count > 8 THEN
            effectiveCount := 8;
        ELSE
            effectiveCount := count;
        END_IF;
        
        // Accumulate sum in DINT to avoid overflow
        sum := 0;
        IF effectiveCount >= 1 THEN
            sum := sum + values[1];
        END_IF;
        IF effectiveCount >= 2 THEN
            sum := sum + values[2];
        END_IF;
        IF effectiveCount >= 3 THEN
            sum := sum + values[3];
        END_IF;
        IF effectiveCount >= 4 THEN
            sum := sum + values[4];
        END_IF;
        IF effectiveCount >= 5 THEN
            sum := sum + values[5];
        END_IF;
        IF effectiveCount >= 6 THEN
            sum := sum + values[6];
        END_IF;
        IF effectiveCount >= 7 THEN
            sum := sum + values[7];
        END_IF;
        IF effectiveCount >= 8 THEN
            sum := sum + values[8];
        END_IF;
        
        // Compute average as REAL
        avgOut := DINT_TO_REAL(sum) / DINT_TO_REAL(effectiveCount);
    ELSE
        // Hold previous value when disabled or no valid samples
        avgOut := prevAvgOut;
    END_IF;
    
    // Update latched output for next scan
    prevAvgOut := avgOut;
END_FUNCTION_BLOCK