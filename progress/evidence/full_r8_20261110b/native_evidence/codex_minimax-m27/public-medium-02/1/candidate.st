FUNCTION_BLOCK FB
VAR_INPUT
    count : DINT;
END_VAR
VAR_IN_OUT
    analogValues : ARRAY[1..8] OF INT;
    channels : ARRAY[1..8] OF ST_AnalogChannel;
END_VAR
VAR
    i : INT;
    rawReal : REAL;
END_VAR

IF count < 1 THEN
    RETURN;
END_IF;

i := 1;
WHILE i <= DINT_TO_INT(count) DO
    IF channels[i].enable THEN
        IF channels[i].measuringMode < 0 OR channels[i].measuringMode > 2 THEN
            channels[i].retVal := 16#8001;
        ELSIF channels[i].hiLIM <= channels[i].loLIM THEN
            channels[i].retVal := 16#8002;
        ELSE
            CASE channels[i].measuringMode OF
                0:
                    rawReal := INT_TO_REAL(analogValues[i]);
                    IF channels[i].bipolar THEN
                        channels[i].outputValue := channels[i].loLIM +
                            (rawReal + 27648.0) * (channels[i].hiLIM - channels[i].loLIM) / 55296.0;
                    ELSE
                        channels[i].outputValue := channels[i].loLIM +
                            rawReal * (channels[i].hiLIM - channels[i].loLIM) / 27648.0;
                    END_IF;
                1:
                    channels[i].outputValue := INT_TO_REAL(analogValues[i]) / 10.0;
                2:
                    channels[i].outputValue := INT_TO_REAL(analogValues[i]) / 100.0;
            END_CASE;
            channels[i].retVal := 16#0000;
        END_IF;
    END_IF;
    i := i + 1;
END_WHILE;

END_FUNCTION_BLOCK