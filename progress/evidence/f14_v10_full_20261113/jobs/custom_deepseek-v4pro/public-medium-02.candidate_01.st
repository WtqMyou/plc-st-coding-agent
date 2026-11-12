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

(*
ENGINEERING_CONTRACT
Activation: process first count ordinal channels, count >= 0, clamped to min array lengths.
Enable: only channels[].enable = TRUE is evaluated; disabled rows retain previous retVal/outputValue.
retVal: for enabled rows write WORD#0 on success; WORD#16#8001 invalid measuringMode (PUB006); WORD#16#8002 hiLIM<=loLIM (PUB007).
Priority/simultaneous checks: measuringMode validity checked before hiLIM<=loLIM; simultaneous invalid mode and bad limits yields 16#8001 (unspecified, chosen).
outputValue: written only for enabled successful conversions; mode0 linear scaling clamped to 0/27648 or -27648/27648 (PUB003); mode1 raw/10 (PUB004); mode2 raw/100 (PUB005).
Read-only: analogValues unchanged; configuration fields only read (PUB001, PUB002).
Bounds: match by ordinal from each array lower bound; invalid count processes none.
Units: raw INT, output REAL, limits REAL; no time.
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
    tmp_lbA : DINT;
    tmp_lbC : DINT;
    tmp_availA : DINT;
    tmp_availC : DINT;
    tmp_process : DINT;
    tmp_i : DINT;
    tmp_idxA : DINT;
    tmp_idxC : DINT;
    tmp_raw : INT;
    tmp_rawReal : REAL;
    tmp_frac : REAL;
END_VAR

tmp_lbA := LOWER_BOUND(analogValues, 1);
tmp_lbC := LOWER_BOUND(channels, 1);
tmp_availA := UPPER_BOUND(analogValues, 1) - tmp_lbA + 1;
tmp_availC := UPPER_BOUND(channels, 1) - tmp_lbC + 1;

tmp_process := count;
IF tmp_process < 0 THEN
    tmp_process := 0;
END_IF;
IF tmp_process > tmp_availA THEN
    tmp_process := tmp_availA;
END_IF;
IF tmp_process > tmp_availC THEN
    tmp_process := tmp_availC;
END_IF;

FOR tmp_i := 0 TO tmp_process - 1 DO
    tmp_idxA := tmp_lbA + tmp_i;
    tmp_idxC := tmp_lbC + tmp_i;

    IF channels[tmp_idxC].enable THEN
        channels[tmp_idxC].retVal := WORD#0;

        IF (channels[tmp_idxC].measuringMode < 0) OR (channels[tmp_idxC].measuringMode > 2) THEN
            channels[tmp_idxC].retVal := WORD#16#8001;
            (* skip conversion; outputValue unchanged *)
        ELSIF channels[tmp_idxC].hiLIM <= channels[tmp_idxC].loLIM THEN
            channels[tmp_idxC].retVal := WORD#16#8002;
            (* skip conversion; outputValue unchanged *)
        ELSE
            tmp_raw := analogValues[tmp_idxA];
            tmp_rawReal := INT_TO_REAL(tmp_raw);

            CASE channels[tmp_idxC].measuringMode OF
                0:
                    IF channels[tmp_idxC].bipolar THEN
                        IF tmp_rawReal < -27648.0 THEN
                            tmp_rawReal := -27648.0;
                        ELSIF tmp_rawReal > 27648.0 THEN
                            tmp_rawReal := 27648.0;
                        END_IF;
                        tmp_frac := (tmp_rawReal + 27648.0) / 55296.0;
                    ELSE
                        IF tmp_rawReal < 0.0 THEN
                            tmp_rawReal := 0.0;
                        ELSIF tmp_rawReal > 27648.0 THEN
                            tmp_rawReal := 27648.0;
                        END_IF;
                        tmp_frac := tmp_rawReal / 27648.0;
                    END_IF;

                    channels[tmp_idxC].outputValue := channels[tmp_idxC].loLIM
                        + tmp_frac * (channels[tmp_idxC].hiLIM - channels[tmp_idxC].loLIM);

                1:
                    channels[tmp_idxC].outputValue := tmp_rawReal / 10.0;

                2:
                    channels[tmp_idxC].outputValue := tmp_rawReal / 100.0;

                ELSE
                    (* unreachable due to mode check above *)
                END_CASE;
        END_IF;
    END_IF;
END_FOR;

END_FUNCTION_BLOCK