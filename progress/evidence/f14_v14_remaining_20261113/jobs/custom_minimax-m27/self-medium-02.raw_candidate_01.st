(* ENGINEERING_CONTRACT: Moving Average Filter (Ring Buffer, 8-point)
 * ---------------------------------------------------------------
 * Input:  enable (BOOL), rawValue (REAL)
 * Output: filteredValue (REAL), windowFull (BOOL), sampleCount (INT)
 *
 * Behavior per output/state:
 *  filteredValue: Combinational arithmetic mean of 1..8 valid samples;
 *                 held unchanged when enable=FALSE (PUB035/S5).
 *                 Units: REAL average of stored REAL samples.
 *  windowFull:    Latch TRUE after sampleCount first reaches 8 (PUB012);
 *                 reset to FALSE on same scan when enable=FALSE (PUB014).
 *                 No explicit reset input; cleared by enable falling edge.
 *  sampleCount:   Monotonic counter 0..8 while enable=TRUE (PUB015/PUB036);
 *                 forced to 0 on same scan when enable=FALSE (PUB014).
 *                 Same-scan priority: clear dominates on enable falling edge.
 *
 * FIFO eviction: When full (count=8), next write overwrites index 1, then 2...
 * First scan (count=0) writes rawValue to index 1; count becomes 1.
 * PUB IDs: PUB001, PUB002, PUB003, PUB004, PUB005, PUB006, PUB007, PUB008,
 *          PUB009, PUB010, PUB011, PUB012, PUB013, PUB014, PUB015, PUB016,
 *          PUB017, PUB018, PUB019, PUB020, PUB021, PUB022, PUB023, PUB024,
 *          PUB025, PUB026, PUB027, PUB028, PUB029, PUB030, PUB031, PUB032,
 *          PUB033, PUB034, PUB035, PUB036, PUB037, PUB038
 *
 * CONTRACT_RULES: [{"kind": "hold_until_reset", "output": "windowFull",
 *                   "set_input": null, "reset_input": "enable"}]
 *)
FUNCTION_BLOCK FB
VAR_INPUT
    enable    : BOOL;
    rawValue  : REAL;
END_VAR
VAR_OUTPUT
    filteredValue : REAL := 0.0;
    windowFull    : BOOL := FALSE;
    sampleCount   : INT  := 0;
END_VAR
VAR
    ringBuffer  : ARRAY[1..8] OF REAL;
    writeIndex  : INT  := 0;
    prev_rawValue : REAL := 0.0;
END_VAR

// Same-scan priority: enable falling edge clears state before any other logic
IF NOT enable THEN
    sampleCount := 0;
    writeIndex  := 0;
    windowFull  := FALSE;
    // filteredValue intentionally NOT written -> retains last value (PUB035)
ELSE
    // enable is TRUE: push sample, compute mean
    writeIndex := ((writeIndex + 1) MOD 8) + 1; // circular 1..8
    ringBuffer[writeIndex] := rawValue;

    IF sampleCount < 8 THEN
        sampleCount := sampleCount + 1;
    END_IF

    windowFull := (sampleCount = 8); // latch until disable

    // Compute arithmetic mean over actual valid samples only
    VAR i         : INT;
    VAR tmp_sum   : REAL;
    END_VAR
    tmp_sum := 0.0;
    FOR i := 1 TO sampleCount DO
        tmp_sum := tmp_sum + ringBuffer[i];
    END_FOR
    filteredValue := tmp_sum / TO_REAL(sampleCount);

    prev_rawValue := rawValue;
END_IF

// Propagate outputs (already assigned in branches above)
END_FUNCTION_BLOCK