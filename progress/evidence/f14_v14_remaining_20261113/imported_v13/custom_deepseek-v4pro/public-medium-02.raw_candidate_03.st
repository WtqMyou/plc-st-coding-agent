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
   Loop count: count limited to 0..min(array lengths); ordinal start at each array lower bound (PUB001).
   channels[].retVal: activated on enabled scan; invalid mode -> 16#8001, invalid limits -> 16#8002,
   success -> 0 (PUB006, PUB007, PUB008).
   channels[].outputValue: written only on successful conversion; mode 0 linear scaling,
   mode 1 /10, mode 2 /100 (PUB003, PUB004, PUB005).
   Disabled channels retain prior retVal/outputValue (unspecified retention interpretation).
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
    local_i : DINT;
    local_n : DINT;
    local_analog_idx : DINT;
    local_channel_idx : DINT;
    local_raw : INT;
    local_mode : INT;
    local_min_len : DINT;
    local_ch_len : DINT;
    local_raw_min : REAL;
    local_raw_max : REAL;
    local_span_raw : REAL;
    local_ratio : REAL;
END_VAR

local_n := count;
IF local_n < 0 THEN
    local_n := 0;
END_IF;

local_min_len := UPPER_BOUND(analogValues, 1) - LOWER_BOUND(analogValues, 1) + 1;
local_ch_len := UPPER_BOUND(channels, 1) - LOWER_BOUND(channels, 1) + 1;
IF local_min_len > local_ch_len THEN
    local_min_len := local_ch_len;
END_IF;
IF local_n > local_min_len THEN
    local_n := local_min_len;
END_IF;

IF local_n > 0 THEN
    FOR local_i := 0 TO local_n - 1 DO
        local_analog_idx := LOWER_BOUND(analogValues, 1) + local_i;
        local_channel_idx := LOWER_BOUND(channels, 1) + local_i;

        IF channels[local_channel_idx].enable THEN
            local_mode := channels[local_channel_idx].measuringMode;

            IF (local_mode <> 0) AND (local_mode <> 1) AND (local_mode <> 2) THEN
                channels[local_channel_idx].retVal := 16#8001;
                (* skip conversion: outputValue unchanged *)
            ELSIF channels[local_channel_idx].hiLIM <= channels[local_channel_idx].loLIM THEN
                channels[local_channel_idx].retVal := 16#8002;
                (* skip conversion: outputValue unchanged *)
            ELSE
                channels[local_channel_idx].retVal := 0;
                CASE local_mode OF
                    0:
                        local_raw := analogValues[local_analog_idx];
                        IF channels[local_channel_idx].bipolar THEN
                            local_raw_min := -27648.0;
                            local_raw_max := 27648.0;
                        ELSE
                            local_raw_min := 0.0;
                            local_raw_max := 27648.0;
                        END_IF;

                        local_span_raw := local_raw_max - local_raw_min;
                        local_ratio := (TO_REAL(local_raw) - local_raw_min) / local_span_raw;
                        channels[local_channel_idx].outputValue := channels[local_channel_idx].loLIM
                            + local_ratio * (channels[local_channel_idx].hiLIM - channels[local_channel_idx].loLIM);

                    1:
                        channels[local_channel_idx].outputValue := TO_REAL(analogValues[local_analog_idx]) / 10.0;

                    2:
                        channels[local_channel_idx].outputValue := TO_REAL(analogValues[local_analog_idx]) / 100.0;
                END_CASE;
            END_IF;
        ELSE
            (* disabled: no writes to retVal or outputValue *)
        END_IF;
    END_FOR;
END_IF;

END_FUNCTION_BLOCK