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
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    count : DINT;
END_VAR
VAR_IN_OUT
    analogValues : ARRAY[1..8] OF INT;
    channels : ARRAY[1..8] OF ST_AnalogChannel;
END_VAR
VAR
    i : DINT;
    limit : DINT;
    rawReal : REAL;
    scaledValue : REAL;
END_VAR

    IF count < 1 THEN
        RETURN;
    END_IF

    IF count > 8 THEN
        limit := 8;
    ELSE
        limit := count;
    END_IF

    FOR i := 1 TO limit DO
        IF channels[i].enable THEN
            IF (channels[i].measuringMode < 0) OR (channels[i].measuringMode > 2) THEN
                channels[i].retVal := 16#8001;
                (* outputValue unchanged *)
            ELSIF channels[i].hiLIM <= channels[i].loLIM THEN
                channels[i].retVal := 16#8002;
                (* outputValue unchanged *)
            ELSE
                channels[i].retVal := 0;
                rawReal := INT_TO_REAL(analogValues[i]);
                CASE channels[i].measuringMode OF
                    0:
                        IF channels[i].bipolar THEN
                            scaledValue := channels[i].loLIM + (rawReal + 27648.0) * (channels[i].hiLIM - channels[i].loLIM) / 55296.0;
                        ELSE
                            scaledValue := channels[i].loLIM + rawReal * (channels[i].hiLIM - channels[i].loLIM) / 27648.0;
                        END_IF
                        channels[i].outputValue := scaledValue;
                    1:
                        channels[i].outputValue := rawReal / 10.0;
                    2:
                        channels[i].outputValue := rawReal / 100.0;
                END_CASE
            END_IF
        END_IF
    END_FOR

END_FUNCTION_BLOCK