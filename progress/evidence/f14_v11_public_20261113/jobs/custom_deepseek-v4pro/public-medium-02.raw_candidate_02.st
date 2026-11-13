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
    tmp_i : DINT;
    tmp_process_count : DINT;
    tmp_analog_lower : DINT;
    tmp_channel_lower : DINT;
    tmp_analog_len : DINT;
    tmp_channel_len : DINT;
    tmp_raw : INT;
    tmp_raw_real : REAL;
    tmp_span : REAL;
    tmp_range : REAL;
END_VAR

(* ENGINEERING_CONTRACT
   Outputs:
   channels[].retVal : activation = enabled channel processed; retention = written only then; reset = none; priority = mode error before limit error; units: WORD.
   channels[].outputValue : activation = successful conversion only; retention = unchanged on skip/error/disabled; reset = none; units: REAL.
   Disabled channels: no writes.
   Mode 0 scaling boundaries: unipolar raw 0..27648 maps [loLIM,hiLIM], bipolar raw -27648..27648 maps [loLIM,hiLIM]; no clamping specified (PUB003).
   Mode 1/2 scale raw/10, raw/100 (PUB004, PUB005).
   Count represents ordinal positions from each array lower bound; caller valid 0..min lengths (PUB001). Cap invalid high count to available.
   Priority for invalid mode vs limit: invalid mode 16#8001 checked first, then limit 16#8002 (PUB006, PUB007).
*)

(* CONTRACT_RULES [] *)

tmp_analog_lower := LOWER_BOUND(analogValues, 1);
tmp_channel_lower := LOWER_BOUND(channels, 1);
tmp_analog_len := UPPER_BOUND(analogValues, 1) - tmp_analog_lower + 1;
tmp_channel_len := UPPER_BOUND(channels, 1) - tmp_channel_lower + 1;

IF count <= 0 THEN
    RETURN;
END_IF;

tmp_process_count := count;
IF tmp_process_count > tmp_analog_len THEN
    tmp_process_count := tmp_analog_len;
END_IF;
IF tmp_process_count > tmp_channel_len THEN
    tmp_process_count := tmp_channel_len;
END_IF;

FOR tmp_i := 0 TO tmp_process_count - 1 DO
    IF channels[tmp_channel_lower + tmp_i].enable THEN
        IF channels[tmp_channel_lower + tmp_i].measuringMode < 0 OR
           channels[tmp_channel_lower + tmp_i].measuringMode > 2 THEN
            channels[tmp_channel_lower + tmp_i].retVal := 16#8001;
        ELSIF channels[tmp_channel_lower + tmp_i].hiLIM <= channels[tmp_channel_lower + tmp_i].loLIM THEN
            channels[tmp_channel_lower + tmp_i].retVal := 16#8002;
        ELSE
            channels[tmp_channel_lower + tmp_i].retVal := 0;
            tmp_raw := analogValues[tmp_analog_lower + tmp_i];
            tmp_raw_real := TO_REAL(tmp_raw);
            CASE channels[tmp_channel_lower + tmp_i].measuringMode OF
                0:
                    tmp_span := channels[tmp_channel_lower + tmp_i].hiLIM - channels[tmp_channel_lower + tmp_i].loLIM;
                    IF channels[tmp_channel_lower + tmp_i].bipolar THEN
                        tmp_range := 55296.0;
                        channels[tmp_channel_lower + tmp_i].outputValue :=
                            channels[tmp_channel_lower + tmp_i].loLIM +
                            ((tmp_raw_real + 27648.0) / tmp_range) * tmp_span;
                    ELSE
                        tmp_range := 27648.0;
                        channels[tmp_channel_lower + tmp_i].outputValue :=
                            channels[tmp_channel_lower + tmp_i].loLIM +
                            (tmp_raw_real / tmp_range) * tmp_span;
                    END_IF;
                1:
                    channels[tmp_channel_lower + tmp_i].outputValue := tmp_raw_real / 10.0;
                2:
                    channels[tmp_channel_lower + tmp_i].outputValue := tmp_raw_real / 100.0;
            END_CASE;
        END_IF;
    END_IF;
END_FOR;

END_FUNCTION_BLOCK