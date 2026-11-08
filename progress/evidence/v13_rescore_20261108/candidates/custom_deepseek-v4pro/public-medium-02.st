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
    i : INT;
    raw : INT;
    rawReal : REAL;
    mapped : REAL;
    rangeLow : REAL := -27648.0;
    rangeHigh : REAL := 27648.0;
    unipolarHigh : REAL := 27648.0;
    unipolarLow : REAL := 0.0;
    scaleSpan : REAL;
    rawSpan : REAL;
END_VAR

    FOR i := 1 TO 8 DO
        IF i > count THEN
            EXIT;
        END_IF;

        IF channels[i].enable THEN
            IF (channels[i].measuringMode = 0) OR
               (channels[i].measuringMode = 1) OR
               (channels[i].measuringMode = 2) THEN

                IF channels[i].hiLIM > channels[i].loLIM THEN
                    raw := analogValues[i];
                    rawReal := INT_TO_REAL(raw);

                    CASE channels[i].measuringMode OF
                        0:
                            IF channels[i].bipolar THEN
                                rawSpan := rangeHigh - rangeLow;  (* 55296.0 *)
                                scaleSpan := channels[i].hiLIM - channels[i].loLIM;
                                mapped := channels[i].loLIM +
                                          (rawReal - rangeLow) / rawSpan * scaleSpan;
                            ELSE
                                rawSpan := unipolarHigh - unipolarLow; (* 27648.0 *)
                                scaleSpan := channels[i].hiLIM - channels[i].loLIM;
                                mapped := channels[i].loLIM +
                                          (rawReal - unipolarLow) / rawSpan * scaleSpan;
                            END_IF;

                        1:
                            mapped := rawReal / 10.0;

                        2:
                            mapped := rawReal / 100.0;
                    ELSE
                        mapped := 0.0; (* should never be reached *)
                    END_CASE;

                    channels[i].outputValue := mapped;
                    channels[i].retVal := 0;
                ELSE
                    channels[i].retVal := 16#8002;
                    (* outputValue unchanged *)
                END_IF;

            ELSE
                channels[i].retVal := 16#8001;
                (* outputValue unchanged *)
            END_IF;

        (* enable = FALSE: nothing is written to retVal or outputValue *)
        END_IF;
    END_FOR;

END_FUNCTION_BLOCK