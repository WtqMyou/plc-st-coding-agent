{attribute 'hide'}
TYPE ST_AnalogChannel : STRUCT
    enable        : BOOL;
    hiLIM         : REAL;
    loLIM         : REAL;
    bipolar       : BOOL;
    measuringMode : INT;
    retVal        : WORD;
    outputValue   : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_AnalogBatchProcessing
VAR_INPUT
END_VAR
VAR_IN_OUT
    count        : DINT;
    analogValues : ARRAY[*] OF INT;
    channels     : ARRAY[*] OF ST_AnalogChannel;
END_VAR
VAR
    tmp_i        : DINT;
    tmp_base     : DINT;
    tmp_raw      : INT;
    tmp_norm     : REAL;
END_VAR

(*
ENGINEERING_CONTRACT
================================================================================
| Output/State      | Activation         | Retention     | Reset          | Scan  | Units           |
|-------------------|--------------------|---------------|----------------|-------|-----------------|
| channels[].retVal | Every enabled chan | Per-call clear| Caller clears  | Final | 16#hex status   |
| channels[].outputValue | Every enabled chan | Caller retains | Caller clears  | Final | REAL engineering|
|-------------------|--------------------|---------------|----------------|-------|-----------------|
PUB001: Process count channels from ordinal position 0 of each array.
PUB002: measuringMode 0=linear(bipolar selectable), 1=stdTemp(raw/10), 2=climTemp(raw/100).
PUB003: Invalid measuringMode -> retVal=16#8001, skip conversion.
PUB004: hiLIM <= loLIM -> retVal=16#8002, skip conversion.
PUB005: Non-temperature linear: unipolar 0..27648->loLIM..hiLIM; bipolar -27648..27648->loLIM..hiLIM.
PUB006: Standard temperature: outputValue = raw * 0.1.
PUB007: Climatic temperature: outputValue = raw * 0.01.
PUB008: Caller provides count 0..min(array lengths); arrays matched by ordinal position.
================================================================================
CONTRACT_RULES []
*)

tmp_base := LOWER_BOUND(analogValues, 1);

FOR tmp_i := 0 TO count - 1 DO
    IF NOT channels[tmp_base + tmp_i].enable THEN
        CONTINUE; // Skip disabled channel
    END_IF

    // Validate measuringMode
    IF channels[tmp_base + tmp_i].measuringMode < 0 OR channels[tmp_base + tmp_i].measuringMode > 2 THEN
        channels[tmp_base + tmp_i].retVal := 16#8001;
        CONTINUE;
    END_IF

    // Validate range
    IF channels[tmp_base + tmp_i].hiLIM <= channels[tmp_base + tmp_i].loLIM THEN
        channels[tmp_base + tmp_i].retVal := 16#8002;
        CONTINUE;
    END_IF

    tmp_raw := analogValues[tmp_base + tmp_i];

    CASE channels[tmp_base + tmp_i].measuringMode OF
        0: // Non-temperature linear scaling
            IF channels[tmp_base + tmp_i].bipolar THEN
                // Bipolar: -27648..27648 -> loLIM..hiLIM
                tmp_norm := INT_TO_REAL(tmp_raw + 27648) / 55296.0;
            ELSE
                // Unipolar: 0..27648 -> loLIM..hiLIM
                tmp_norm := INT_TO_REAL(tmp_raw) / 27648.0;
            END_IF
            channels[tmp_base + tmp_i].outputValue := channels[tmp_base + tmp_i].loLIM + tmp_norm * (channels[tmp_base + tmp_i].hiLIM - channels[tmp_base + tmp_i].loLIM);
            channels[tmp_base + tmp_i].retVal := 16#0000;

        1: // Standard temperature: raw / 10
            channels[tmp_base + tmp_i].outputValue := INT_TO_REAL(tmp_raw) / 10.0;
            channels[tmp_base + tmp_i].retVal := 16#0000;

        2: // Climatic temperature: raw / 100
            channels[tmp_base + tmp_i].outputValue := INT_TO_REAL(tmp_raw) / 100.0;
            channels[tmp_base + tmp_i].retVal := 16#0000;
    END_CASE;
END_FOR;

END_FUNCTION_BLOCK