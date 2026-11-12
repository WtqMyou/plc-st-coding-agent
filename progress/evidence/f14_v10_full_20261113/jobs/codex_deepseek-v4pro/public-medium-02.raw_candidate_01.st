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

(* ENGINEERING_CONTRACT
   count: process ordinal positions 0..count-1 from each array's own lower bound, limited to both upper bounds.
   enable=FALSE: channel is skipped; retVal/outputValue are not written (unspecified by PUB002).
   mode invalid: retVal=16#8001, outputValue unchanged, conversion skipped (PUB006).
   hiLIM<=loLIM: retVal=16#8002, outputValue unchanged, conversion skipped (PUB007).
   success: retVal=16#0000, outputValue set from analogValues[ordinal] (PUB003/PUB004/PUB005).
   mode0 unipolar: loLIM + raw/27648*(hiLIM-loLIM); bipolar: loLIM + (raw+27648)/55296*(hiLIM-loLIM).
   mode1: raw/10.0; mode2: raw/100.0. Raw INT converted explicitly to REAL.
   no latches/edges/retention; each invocation recomputes selected enabled channels (PUB001).
*)

(* CONTRACT_RULES [] *)

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
    tmp_analog_index : DINT;
    tmp_channel_index : DINT;
    tmp_raw : REAL;
END_VAR

tmp_analog_lower := LOWER_BOUND(analogValues, 1);
tmp_channel_lower := LOWER_BOUND(channels, 1);
tmp_analog_len := UPPER_BOUND(analogValues, 1) - tmp_analog_lower + 1;
tmp_channel_len := UPPER_BOUND(channels, 1) - tmp_channel_lower + 1;

tmp_process_count := count;
IF tmp_process_count < 0 THEN
    tmp_process_count := 0;
END_IF;
IF tmp_process_count > tmp_analog_len THEN
    tmp_process_count := tmp_analog_len;
END_IF;
IF tmp_process_count > tmp_channel_len THEN
    tmp_process_count := tmp_channel_len;
END_IF;

FOR tmp_i := 0 TO tmp_process_count - 1 DO
    tmp_analog_index := tmp_analog_lower + tmp_i;
    tmp_channel_index := tmp_channel_lower + tmp_i;

    IF channels[tmp_channel_index].enable THEN
        IF (channels[tmp_channel_index].measuringMode <> 0)
           AND (channels[tmp_channel_index].measuringMode <> 1)
           AND (channels[tmp_channel_index].measuringMode <> 2) THEN
            channels[tmp_channel_index].retVal := 16#8001;
        ELSIF channels[tmp_channel_index].hiLIM <= channels[tmp_channel_index].loLIM THEN
            channels[tmp_channel_index].retVal := 16#8002;
        ELSE
            tmp_raw := INT_TO_REAL(analogValues[tmp_analog_index]);

            CASE channels[tmp_channel_index].measuringMode OF
                0:
                    IF channels[tmp_channel_index].bipolar THEN
                        channels[tmp_channel_index].outputValue :=
                            channels[tmp_channel_index].loLIM
                            + ((tmp_raw + 27648.0) / 55296.0)
                            * (channels[tmp_channel_index].hiLIM - channels[tmp_channel_index].loLIM);
                    ELSE
                        channels[tmp_channel_index].outputValue :=
                            channels[tmp_channel_index].loLIM
                            + (tmp_raw / 27648.0)
                            * (channels[tmp_channel_index].hiLIM - channels[tmp_channel_index].loLIM);
                    END_IF;
                1:
                    channels[tmp_channel_index].outputValue := tmp_raw / 10.0;
                2:
                    channels[tmp_channel_index].outputValue := tmp_raw / 100.0;
            END_CASE;

            channels[tmp_channel_index].retVal := 16#0000;
        END_IF;
    END_IF;
END_FOR;

END_FUNCTION_BLOCK