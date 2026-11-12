TYPE ST_AnalogChannel :
STRUCT
    enable : BOOL;
    hiLIM : REAL;
    loLIM : REAL;
    bipolar : BOOL;
    measuringMode : INT;
    retVal : WORD;
    outputValue : REAL;
END_STRUCT;
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
    raw : INT;
    rawReal : REAL;
    valueIndex : DINT;
    channelIndex : DINT;
END_VAR

FOR i := 0 TO count - 1 DO
    valueIndex := LOWER_BOUND(analogValues, 1) + i;
    channelIndex := LOWER_BOUND(channels, 1) + i;

    IF channels[channelIndex].enable THEN
        raw := analogValues[valueIndex];

        IF (channels[channelIndex].measuringMode <> 0) AND
           (channels[channelIndex].measuringMode <> 1) AND
           (channels[channelIndex].measuringMode <> 2) THEN
            channels[channelIndex].retVal := WORD#16#8001;
        ELSIF channels[channelIndex].hiLIM <= channels[channelIndex].loLIM THEN
            channels[channelIndex].retVal := WORD#16#8002;
        ELSE
            channels[channelIndex].retVal := WORD#0;
            rawReal := INT_TO_REAL(raw);

            IF channels[channelIndex].measuringMode = 0 THEN
                IF channels[channelIndex].bipolar THEN
                    channels[channelIndex].outputValue :=
                        channels[channelIndex].loLIM +
                        ((rawReal + REAL#27648.0) / REAL#55296.0) *
                        (channels[channelIndex].hiLIM - channels[channelIndex].loLIM);
                ELSE
                    channels[channelIndex].outputValue :=
                        channels[channelIndex].loLIM +
                        (rawReal / REAL#27648.0) *
                        (channels[channelIndex].hiLIM - channels[channelIndex].loLIM);
                END_IF;
            ELSIF channels[channelIndex].measuringMode = 1 THEN
                channels[channelIndex].outputValue := rawReal / REAL#10.0;
            ELSE
                channels[channelIndex].outputValue := rawReal / REAL#100.0;
            END_IF;
        END_IF;
    END_IF;
END_FOR;

END_FUNCTION_BLOCK