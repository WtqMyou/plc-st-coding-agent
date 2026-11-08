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
    idx : DINT;
    rawValue : REAL;
    scalingSpan : REAL;
END_VAR

IF count >= 1 THEN
    FOR idx := 1 TO count DO
        IF channels[idx].enable THEN
            channels[idx].retVal := 0;

            IF (channels[idx].measuringMode < 0) OR (channels[idx].measuringMode > 2) THEN
                channels[idx].retVal := 16#8001;
            ELSIF channels[idx].hiLIM <= channels[idx].loLIM THEN
                channels[idx].retVal := 16#8002;
            ELSE
                rawValue := INT_TO_REAL(analogValues[idx]);

                IF channels[idx].measuringMode = 0 THEN
                    scalingSpan := channels[idx].hiLIM - channels[idx].loLIM;

                    IF channels[idx].bipolar THEN
                        channels[idx].outputValue := channels[idx].loLIM
                            + ((rawValue + 27648.0) * scalingSpan / 55296.0);
                    ELSE
                        channels[idx].outputValue := channels[idx].loLIM
                            + (rawValue * scalingSpan / 27648.0);
                    END_IF;

                ELSIF channels[idx].measuringMode = 1 THEN
                    channels[idx].outputValue := rawValue / 10.0;

                ELSE
                    channels[idx].outputValue := rawValue / 100.0;
                END_IF;
            END_IF;
        END_IF;
    END_FOR;
END_IF;

END_FUNCTION_BLOCK