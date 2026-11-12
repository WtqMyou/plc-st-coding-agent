TYPE ST_AnalogChannel :
STRUCT
    enable : BOOL;
    hiLIM : REAL;
    loLIM : REAL;
    bipolar : BOOL;
    measuringMode : INT;
    retVal : WORD;
    outputValue : REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK AnalogBatchProcessing
VAR_INPUT
    count : DINT;
END_VAR
VAR_IN_OUT
    analogValues : ARRAY[*] OF INT;
    channels : ARRAY[*] OF ST_AnalogChannel;
END_VAR
VAR
    i : DINT;
    idxA : DINT;
    idxC : DINT;
    lbA : DINT;
    lbC : DINT;
    raw : INT;
    rawReal : REAL;
    rawMin : REAL;
    rawSpan : REAL;
    engSpan : REAL;
END_VAR

    lbA := LOWER_BOUND(analogValues, 1);
    lbC := LOWER_BOUND(channels, 1);

    FOR i := 0 TO count - 1 DO
        idxA := lbA + i;
        idxC := lbC + i;

        IF channels[idxC].enable THEN
            IF channels[idxC].measuringMode <> 0 AND channels[idxC].measuringMode <> 1 AND channels[idxC].measuringMode <> 2 THEN
                channels[idxC].retVal := WORD#16#8001;
            ELSIF channels[idxC].hiLIM <= channels[idxC].loLIM THEN
                channels[idxC].retVal := WORD#16#8002;
            ELSE
                raw := analogValues[idxA];
                rawReal := INT_TO_REAL(raw);
                CASE channels[idxC].measuringMode OF
                    0:
                        IF channels[idxC].bipolar THEN
                            rawMin := -27648.0;
                            rawSpan := 55296.0;
                        ELSE
                            rawMin := 0.0;
                            rawSpan := 27648.0;
                        END_IF;
                        engSpan := channels[idxC].hiLIM - channels[idxC].loLIM;
                        channels[idxC].outputValue := channels[idxC].loLIM + (rawReal - rawMin) * engSpan / rawSpan;
                    1:
                        channels[idxC].outputValue := rawReal / 10.0;
                    2:
                        channels[idxC].outputValue := rawReal / 100.0;
                END_CASE;
                channels[idxC].retVal := 0;
            END_IF;
        END_IF;
    END_FOR;

END_FUNCTION_BLOCK