FUNCTION_BLOCK FB
VAR
    lastAvgOut : REAL := 0.0;
END_VAR
VAR_OUTPUT
    avgOut : REAL := 0.0;
END_VAR
VAR_INPUT
    enable      : BOOL;
    values      : ARRAY[1..8] OF INT;
    count       : INT;
    avgEnable   : BOOL;
END_VAR
VAR
    sum   : DINT;
    i     : INT;
    n     : INT;
END_VAR

// [S2] enable = FALSE: keep previous
// [S5] avgEnable = FALSE: keep previous
// [S1] count <= 0: keep previous, avoid div-by-zero
// Guard: only compute when all conditions satisfied
IF enable AND avgEnable AND (count > 0) THEN
    // [S6] clamp count to array bounds [1..8]
    IF count > 8 THEN
        n := 8;
    ELSE
        n := count;
    END_IF;

    // Wide-type sum to prevent INT overflow
    sum := 0;
    FOR i := 1 TO n DO
        sum := sum + values[i];
    END_FOR;

    // [S4][S6] REAL division preserves fractional precision
    avgOut := DINT_TO_REAL(sum) / DINT_TO_REAL(n);
    lastAvgOut := avgOut;
ELSE
    avgOut := lastAvgOut;
END_IF;
END_FUNCTION_BLOCK