(* ENGINEERING_CONTRACT
 * PUB001: Batch processing - iterate count channels from array lower bounds
 * PUB002: measuringMode 0 = non-temperature linear scaling (unipolar 0..27648 or bipolar -27648..27648 mapped to loLIM..hiLIM)
 * PUB003: measuringMode 1 = standard temperature, outputValue = raw / 10.0
 * PUB004: measuringMode 2 = climatic temperature, outputValue = raw / 100.0
 * PUB005: Invalid measuringMode (not 0/1/2) -> retVal = 16#8001, skip conversion
 * PUB006: hiLIM <= loLIM -> retVal = 16#8002, skip conversion
 * PUB007: Disabled channels: no modification of retVal or outputValue
 * PUB008: Same-scan execution; TON not required; no edge triggers added
 * Retention: outputValue and retVal updated per enabled-channel scan; no global reset
 *)

(* CONTRACT_RULES [] *)

TYPE ST_AnalogChannel :
STRUCT
    enable        : BOOL;
    hiLIM         : REAL;
    loLIM         : REAL;
    bipolar       : BOOL;
    measuringMode : INT;
    retVal        : WORD;
    outputValue   : REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK FB_AnalogBatchProcessing
VAR_INPUT
    count : DINT;
END_VAR
VAR_IN_OUT
    analogValues : ARRAY[*] OF INT;
    channels     : ARRAY[*] OF ST_AnalogChannel;
END_VAR
VAR
    idx         : DINT;
    rawValue    : INT;
    rawReal     : REAL;
    outReal     : REAL;
    idxStart    : DINT;
    continue    : BOOL;
END_VAR

idxStart := LOWER_BOUND(Arr := analogValues, Dim := 1);

FOR idx := idxStart TO idxStart + count - 1 DO
    continue := FALSE;
    rawValue := analogValues[idx];
    rawReal := TO_REAL(rawValue);
    outReal := 0.0;
    continue := TRUE;
    IF NOT channels[idx].enable THEN
        continue := FALSE;
    END_IF;
    IF continue THEN
        IF channels[idx].measuringMode = 0 THEN
            IF channels[idx].bipolar THEN
                outReal := channels[idx].loLIM + ((rawReal + 27648.0) / 55296.0) * (channels[idx].hiLIM - channels[idx].loLIM);
            ELSE
                outReal := channels[idx].loLIM + (rawReal / 27648.0) * (channels[idx].hiLIM - channels[idx].loLIM);
            END_IF;
        ELSIF channels[idx].measuringMode = 1 THEN
            outReal := rawReal / 10.0;
        ELSIF channels[idx].measuringMode = 2 THEN
            outReal := rawReal / 100.0;
        ELSE
            channels[idx].retVal := 16#8001;
            continue := FALSE;
        END_IF;
    END_IF;
    IF continue THEN
        IF channels[idx].hiLIM <= channels[idx].loLIM THEN
            channels[idx].retVal := 16#8002;
            continue := FALSE;
        END_IF;
    END_IF;
    IF continue THEN
        channels[idx].outputValue := outReal;
        channels[idx].retVal := 16#0000;
    END_IF;
END_FOR;

END_FUNCTION_BLOCK