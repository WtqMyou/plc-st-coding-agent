(* ENGINEERING_CONTRACT
 * Pub: PUB001-006, PUB008-012, PUB015, PUB017, PUB019-022, PUB024-026, PUB028-038
 * Block: FB (8-point moving average with FIFO eviction)
 * 
 * | Output/State     | Activation         | Retention                    | Reset/Deactivation         | Priority | Units        |
 * |------------------|--------------------|------------------------------|-----------------------------|----------|--------------|
 * | filteredValue    | Each enable scan   | Hold last when enable=FALSE  | None (retention required)   | Same-scan| REAL         |
 * | windowFull       | sampleCount=8      | Hold TRUE when full          | Clear on enable=FALSE       | Same-scan| BOOL         |
 * | sampleCount      | +1 per sample<8    | Reset to 0 when enable=FALSE | Clear on enable=FALSE       | Same-scan| INT [0..8]   |
 * | buffer/sum/idx   | Fresh start on enable| Not exposed externally      | Clear on enable=FALSE       | N/A      | VAR statics  |
 * 
 * CONTRACT_RULES []
 *)
FUNCTION_BLOCK FB
VAR_INPUT
    enable    : BOOL;
    rawValue  : REAL;
END_VAR
VAR_OUTPUT
    filteredValue : REAL;
    windowFull    : BOOL;
    sampleCount   : INT;
END_VAR
VAR
    buffer     : ARRAY[0..7] OF REAL := (0,0,0,0,0,0,0,0);
    writeIndex : INT := 0;
    sum        : REAL := 0.0;
END_VAR

IF enable THEN
    (* Fresh start on transition from disabled *)
    IF sampleCount = 0 THEN
        buffer[0] := rawValue;
        buffer[1] := 0.0; buffer[2] := 0.0; buffer[3] := 0.0;
        buffer[4] := 0.0; buffer[5] := 0.0; buffer[6] := 0.0; buffer[7] := 0.0;
        writeIndex := 1;
        sum := rawValue;
        sampleCount := 1;
        filteredValue := rawValue;
        windowFull := FALSE;
    ELSE
        (* Normal operation *)
        IF sampleCount < 8 THEN
            buffer[writeIndex] := rawValue;
            sum := sum + rawValue;
            writeIndex := (writeIndex + 1) MOD 8;
            sampleCount := sampleCount + 1;
        ELSE
            (* FIFO eviction when full *)
            sum := sum - buffer[writeIndex];
            buffer[writeIndex] := rawValue;
            writeIndex := (writeIndex + 1) MOD 8;
        END_IF;
        filteredValue := sum / INT_TO_REAL(sampleCount);
        IF sampleCount >= 8 THEN
            windowFull := TRUE;
        END_IF;
    END_IF;
ELSE
    sampleCount := 0;
    windowFull := FALSE;
END_IF;

END_FUNCTION_BLOCK