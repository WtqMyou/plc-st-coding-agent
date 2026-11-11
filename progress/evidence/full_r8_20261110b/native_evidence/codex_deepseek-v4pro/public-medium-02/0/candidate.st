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
    rawValue : REAL;
END_VAR

IF count >= 1 THEN
    FOR i := 1 TO 8 DO
        IF i <= count THEN
            IF channels[i].enable THEN
                IF (channels[i].measuringMode < 0) OR (channels[i].measuringMode > 2) THEN
                    channels[i].retVal := 16#8001;
                ELSIF channels[i].hiLIM <= channels[i].loLIM THEN
                    channels[i].retVal := 16#8002;
                ELSE
                    channels[i].retVal := 0;

                    IF channels[i].measuringMode = 0 THEN
                        IF channels[i].bipolar THEN
                            rawValue := INT_TO_REAL(analogValues[i]) + 27648.0;
                            channels[i].outputValue := channels[i].loLIM + rawValue * (channels[i].hiLIM - channels[i].loLIM) / 55296.0;
                        ELSE
                            rawValue := INT_TO_REAL(analogValues[i]);
                            channels[i].outputValue := channels[i].loLIM + rawValue * (channels[i].hiLIM - channels[i].loLIM) / 27648.0;
                        END_IF;
                    ELSIF channels[i].measuringMode = 1 THEN
                        channels[i].outputValue := INT_TO_REAL(analogValues[i]) / 10.0;
                    ELSIF channels[i].measuringMode = 2 THEN
                        channels[i].outputValue := INT_TO_REAL(analogValues[i]) / 100.0;
                    END_IF;
                END_IF;
            END_IF;
        END_IF;
    END_FOR;
END_IF;

END_FUNCTION_BLOCK