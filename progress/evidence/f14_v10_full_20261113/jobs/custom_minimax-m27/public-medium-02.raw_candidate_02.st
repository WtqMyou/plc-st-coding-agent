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
    enable         : BOOL;
    hiLIM          : REAL;
    loLIM          : REAL;
    bipolar        : BOOL;
    measuringMode  : INT;
    retVal         : WORD;
    outputValue    : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_AnalogBatchProcessing
VAR_INPUT
    count : DINT;
END_VAR
VAR_IN_OUT
    analogValues : ARRAY[*] OF INT;
    channels     : ARRAY[*] OF ST_AnalogChannel;
END_VAR
VAR_OUTPUT
END_VAR
VAR
    tmp_i        : DINT;
    tmp_lower    : DINT;
    tmp_raw      : INT;
    tmp_rawReal  : REAL;
    tmp_mode     : INT;
    tmp_bipolar  : BOOL;
    tmp_hiLIM    : REAL;
    tmp_loLIM    : REAL;
    tmp_err      : BOOL;
    tmp_enabled  : BOOL;
END_VAR

tmp_lower := LOWER(analogValues, 1);

FOR tmp_i := 0 TO count - 1 DO
    tmp_err := FALSE;
    tmp_enabled := channels[tmp_lower + tmp_i].enable;

    IF tmp_enabled THEN
        tmp_mode    := channels[tmp_lower + tmp_i].measuringMode;
        tmp_bipolar := channels[tmp_lower + tmp_i].bipolar;
        tmp_hiLIM   := channels[tmp_lower + tmp_i].hiLIM;
        tmp_loLIM   := channels[tmp_lower + tmp_i].loLIM;
        tmp_raw     := analogValues[tmp_lower + tmp_i];
        tmp_rawReal := TO_REAL(tmp_raw);

        IF tmp_mode <> 0 AND tmp_mode <> 1 AND tmp_mode <> 2 THEN
            channels[tmp_lower + tmp_i].retVal := 16#8001;
            tmp_err := TRUE;
        END_IF;

        IF NOT tmp_err AND tmp_hiLIM <= tmp_loLIM THEN
            channels[tmp_lower + tmp_i].retVal := 16#8002;
            tmp_err := TRUE;
        END_IF;

        IF NOT tmp_err THEN
            IF tmp_mode = 0 THEN
                IF tmp_bipolar THEN
                    channels[tmp_lower + tmp_i].outputValue := tmp_loLIM + 
                        ((tmp_rawReal + 27648.0) / 55296.0) * (tmp_hiLIM - tmp_loLIM);
                ELSE
                    channels[tmp_lower + tmp_i].outputValue := tmp_loLIM + 
                        (tmp_rawReal / 27648.0) * (tmp_hiLIM - tmp_loLIM);
                END_IF;
                channels[tmp_lower + tmp_i].retVal := 16#0000;
            ELSIF tmp_mode = 1 THEN
                channels[tmp_lower + tmp_i].outputValue := tmp_rawReal / 10.0;
                channels[tmp_lower + tmp_i].retVal := 16#0000;
            ELSIF tmp_mode = 2 THEN
                channels[tmp_lower + tmp_i].outputValue := tmp_rawReal / 100.0;
                channels[tmp_lower + tmp_i].retVal := 16#0000;
            END_IF;
        END_IF;
    END_IF;
END_FOR;

END_FUNCTION_BLOCK