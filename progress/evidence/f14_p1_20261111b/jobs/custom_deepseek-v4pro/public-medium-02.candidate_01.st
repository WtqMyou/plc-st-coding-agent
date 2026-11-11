FUNCTION_BLOCK AnalogBatchProcessing
VAR_INPUT
    count : DINT;
END_VAR
VAR_IN_OUT
    analogValues : ARRAY [*] OF INT;
    channels : ARRAY [*] OF ST_AnalogChannel;
END_VAR
VAR
    i : DINT;
    numToProcess : DINT;
    aLow : DINT;
    cLow : DINT;
    aLen : DINT;
    cLen : DINT;
    analogIdx : DINT;
    channelIdx : DINT;
    rawValue : INT;
    rawReal : REAL;
    range : REAL;
    norm : REAL;
END_VAR

// Determine array bounds and lengths
aLow := LOWER_BOUND(analogValues, 1);
cLow := LOWER_BOUND(channels, 1);
aLen := UPPER_BOUND(analogValues, 1) - aLow + 1;
cLen := UPPER_BOUND(channels, 1) - cLow + 1;

// Limit processing to the smaller of the two array lengths
IF aLen < cLen THEN
    numToProcess := aLen;
ELSE
    numToProcess := cLen;
END_IF;

// Clamp count to valid range
IF count < 0 THEN
    numToProcess := 0;
ELSIF count < numToProcess THEN
    numToProcess := count;
END_IF;

IF numToProcess > 0 THEN
    FOR i := 0 TO numToProcess - 1 DO
        analogIdx := aLow + i;
        channelIdx := cLow + i;

        IF channels[channelIdx].enable THEN
            IF (channels[channelIdx].measuringMode < 0) OR
               (channels[channelIdx].measuringMode > 2) THEN
                channels[channelIdx].retVal := WORD#16#8001;
            ELSIF channels[channelIdx].hiLIM <= channels[channelIdx].loLIM THEN
                channels[channelIdx].retVal := WORD#16#8002;
            ELSE
                channels[channelIdx].retVal := WORD#16#0000;
                rawValue := analogValues[analogIdx];
                rawReal := INT_TO_REAL(rawValue);

                CASE channels[channelIdx].measuringMode OF
                    0:
                        range := channels[channelIdx].hiLIM - channels[channelIdx].loLIM;
                        IF channels[channelIdx].bipolar THEN
                            norm := (rawReal + 27648.0) / 55296.0;
                        ELSE
                            norm := rawReal / 27648.0;
                        END_IF;
                        channels[channelIdx].outputValue := channels[channelIdx].loLIM + norm * range;

                    1:
                        channels[channelIdx].outputValue := rawReal / 10.0;

                    2:
                        channels[channelIdx].outputValue := rawReal / 100.0;
                END_CASE;
            END_IF;
        END_IF;
    END_FOR;
END_IF;