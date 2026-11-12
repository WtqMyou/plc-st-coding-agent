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

FUNCTION_BLOCK FB_AnalogBatchProcessing
VAR_INPUT
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
    tmp_upper    : DINT;
    tmp_raw      : INT;
    tmp_rawReal  : REAL;
    tmp_mode     : INT;
    tmp_bipolar  : BOOL;
    tmp_hiLIM    : REAL;
    tmp_loLIM    : REAL;
    tmp_err      : BOOL;
END_VAR

tmp_lower := LOWER_BOUND(Arr := analogValues, Dim := 1);
tmp_upper := LOWER_BOUND(Arr := channels, Dim := 1) + count - 1;

FOR tmp_i := 0 TO count - 1 DO
    tmp_err := FALSE;

    (* Access channel by ordinal position from channels lower bound *)
    IF NOT channels[tmp_lower + tmp_i].enable THEN
        (* Disabled channel: leave retVal and outputValue unchanged per PUB007 *)
        CONTINUE;
    END_IF;

    (* Cache channel configuration fields per PUB001 *)
    tmp_mode    := channels[tmp_lower + tmp_i].measuringMode;
    tmp_bipolar := channels[tmp_lower + tmp_i].bipolar;
    tmp_hiLIM   := channels[tmp_lower + tmp_i].hiLIM;
    tmp_loLIM   := channels[tmp_lower + tmp_i].loLIM;
    tmp_raw     := analogValues[tmp_lower + tmp_i];
    tmp_rawReal := TO_REAL(tmp_raw);

    (* Error check: invalid measuringMode per PUB005 *)
    IF tmp_mode <> 0 AND tmp_mode <> 1 AND tmp_mode <> 2 THEN
        channels[tmp_lower + tmp_i].retVal := 16#8001;
        tmp_err := TRUE;
    END_IF;

    (* Error check: hiLIM <= loLIM per PUB006 *)
    IF NOT tmp_err AND tmp_hiLIM <= tmp_loLIM THEN
        channels[tmp_lower + tmp_i].retVal := 16#8002;
        tmp_err := TRUE;
    END_IF;

    (* Skip conversion on error per PUB005/PUB006 *)
    IF tmp_err THEN
        CONTINUE;
    END_IF;

    (* Conversion per measuringMode per PUB002/PUB003/PUB004 *)
    IF tmp_mode = 0 THEN
        (* Non-temperature linear scaling per PUB002 *)
        IF tmp_bipolar THEN
            (* Bipolar: -27648..27648 -> loLIM..hiLIM *)
            channels[tmp_lower + tmp_i].outputValue := tmp_loLIM + 
                ((tmp_rawReal + 27648.0) / (27648.0 - (-27648.0))) * (tmp_hiLIM - tmp_loLIM);
        ELSE
            (* Unipolar: 0..27648 -> loLIM..hiLIM *)
            channels[tmp_lower + tmp_i].outputValue := tmp_loLIM + 
                (tmp_rawReal / 27648.0) * (tmp_hiLIM - tmp_loLIM);
        END_IF;
        channels[tmp_lower + tmp_i].retVal := 16#0000;
    ELSIF tmp_mode = 1 THEN
        (* Standard temperature: one tenth per PUB003 *)
        channels[tmp_lower + tmp_i].outputValue := tmp_rawReal / 10.0;
        channels[tmp_lower + tmp_i].retVal := 16#0000;
    ELSIF tmp_mode = 2 THEN
        (* Climatic temperature: one hundredth per PUB004 *)
        channels[tmp_lower + tmp_i].outputValue := tmp_rawReal / 100.0;
        channels[tmp_lower + tmp_i].retVal := 16#0000;
    END_IF;
END_FOR;

END_FUNCTION_BLOCK