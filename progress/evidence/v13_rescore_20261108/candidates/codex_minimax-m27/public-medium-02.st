TYPE ST_AnalogChannel :
STRUCT
    enable       : BOOL;
    hiLIM        : REAL;
    loLIM        : REAL;
    bipolar      : BOOL;
    measuringMode: INT;
    retVal       : WORD;
    outputValue  : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    count : DINT;
END_VAR
VAR_IN_OUT
    analogValues : ARRAY[1..8] OF INT;
    channels     : ARRAY[1..8] OF ST_AnalogChannel;
END_VAR
VAR
    i   : DINT;
    raw : INT;
END_VAR

IF count < 1 THEN
    RETURN;
END_IF;

FOR i := 1 TO count DO
    IF channels[i].enable THEN
        raw := analogValues[i];

        IF channels[i].measuringMode < 0 OR channels[i].measuringMode > 2 THEN
            channels[i].retVal := 16#8001;
        ELSIF channels[i].hiLIM <= channels[i].loLIM THEN
            channels[i].retVal := 16#8002;
        ELSIF channels[i].measuringMode = 0 THEN
            IF NOT channels[i].bipolar THEN
                channels[i].outputValue := channels[i].loLIM
                    + (INT_TO_REAL(raw) / 27648.0)
                    * (channels[i].hiLIM - channels[i].loLIM);
            ELSE
                channels[i].outputValue := channels[i].loLIM
                    + ((INT_TO_REAL(raw) + 27648.0) / (2.0 * 27648.0))
                    * (channels[i].hiLIM - channels[i].loLIM);
            END_IF;
            channels[i].retVal := 16#0000;
        ELSIF channels[i].measuringMode = 1 THEN
            channels[i].outputValue := INT_TO_REAL(raw) / 10.0;
            channels[i].retVal      := 16#0000;
        ELSIF channels[i].measuringMode = 2 THEN
            channels[i].outputValue := INT_TO_REAL(raw) / 100.0;
            channels[i].retVal      := 16#0000;
        END_IF;
    END_IF;
END_FOR
END_FUNCTION_BLOCK