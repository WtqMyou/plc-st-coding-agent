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

FUNCTION_BLOCK AnalogBatchProcessing
VAR_INPUT
    count : DINT;
END_VAR
VAR_IN_OUT
    analogValues : ARRAY[*] OF INT;
    channels : ARRAY[*] OF ST_AnalogChannel;
END_VAR
VAR
    local_a_lower : DINT;
    local_a_upper : DINT;
    local_c_lower : DINT;
    local_c_upper : DINT;
    local_count : DINT;
    local_i : DINT;
    local_a_idx : DINT;
    local_c_idx : DINT;
    local_raw : INT;
    local_scaled : REAL;
END_VAR

(* ENGINEERING_CONTRACT
- Enabled channels convert; disabled channels retain prior retVal/outputValue (unspecified).
- Count selects the first count ordinal slots from each array lower bound; analog is read-only (PUB001, PUB002).
- Mode 0 maps unipolar raw 0..27648 or bipolar raw -27648..27648 linearly to loLIM..hiLIM; outside raw is extrapolated, not clamped (PUB003).
- Mode 1: outputValue = raw * 0.1. Mode 2: outputValue = raw * 0.01 (PUB004).
- Invalid mode sets 16#8001; hiLIM <= loLIM sets 16#8002. Mode error is checked first; error skips conversion/output update (PUB005, PUB006).
- Valid enabled conversion writes outputValue and retVal = 16#0000.
*)

(* CONTRACT_RULES [] *)

local_a_lower := LOWER_BOUND(analogValues, 1);
local_a_upper := UPPER_BOUND(analogValues, 1);
local_c_lower := LOWER_BOUND(channels, 1);
local_c_upper := UPPER_BOUND(channels, 1);

local_count := count;
IF local_count < 0 THEN
    local_count := 0;
END_IF
IF local_count > (local_a_upper - local_a_lower + 1) THEN
    local_count := local_a_upper - local_a_lower + 1;
END_IF
IF local_count > (local_c_upper - local_c_lower + 1) THEN
    local_count := local_c_upper - local_c_lower + 1;
END_IF

FOR local_i := 0 TO local_count - 1 DO
    local_a_idx := local_a_lower + local_i;
    local_c_idx := local_c_lower + local_i;

    IF channels[local_c_idx].enable THEN
        IF channels[local_c_idx].measuringMode < 0
           OR channels[local_c_idx].measuringMode > 2 THEN
            channels[local_c_idx].retVal := 16#8001;
        ELSIF channels[local_c_idx].hiLIM <= channels[local_c_idx].loLIM THEN
            channels[local_c_idx].retVal := 16#8002;
        ELSE
            local_raw := analogValues[local_a_idx];

            CASE channels[local_c_idx].measuringMode OF
                0:
                    IF channels[local_c_idx].bipolar THEN
                        local_scaled := channels[local_c_idx].loLIM
                                        + ((TO_REAL(local_raw) + 27648.0) / 55296.0)
                                          * (channels[local_c_idx].hiLIM - channels[local_c_idx].loLIM);
                    ELSE
                        local_scaled := channels[local_c_idx].loLIM
                                        + (TO_REAL(local_raw) / 27648.0)
                                          * (channels[local_c_idx].hiLIM - channels[local_c_idx].loLIM);
                    END_IF

                1:
                    local_scaled := TO_REAL(local_raw) * 0.1;

                2:
                    local_scaled := TO_REAL(local_raw) * 0.01;
            END_CASE

            channels[local_c_idx].outputValue := local_scaled;
            channels[local_c_idx].retVal := 16#0000;
        END_IF
    END_IF
END_FOR

END_FUNCTION_BLOCK