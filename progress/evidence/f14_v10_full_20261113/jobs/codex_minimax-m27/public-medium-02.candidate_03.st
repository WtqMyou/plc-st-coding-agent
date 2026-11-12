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

FUNCTION_BLOCK AnalogBatchProcessing
VAR_INPUT
    count : DINT;
END_VAR
VAR_IN_OUT
    analogValues : ARRAY[*] OF INT;
    channels     : ARRAY[*] OF ST_AnalogChannel;
END_VAR
VAR
    tmp_i             : DINT;
    tmp_channelsLower : DINT;
    tmp_analogLower   : DINT;
    tmp_rawMin        : REAL;
    tmp_rawMax        : REAL;
    tmp_rawRange      : REAL;
    tmp_engRange      : REAL;
    tmp_raw           : INT;
    tmp_analogVal     : REAL;
END_VAR
(* CONTRACT_RULES [] *)
(* ENGINEERING_CONTRACT
 * Activation:       Each scan processes up to 'count' channels sequentially.
 * Retention:        retVal and outputValue are overwritten each scan; no latching.
 * Explicit Reset:   None specified; outputs refresh every scan.
 * Same-scan Priority: Sequential ordinal processing; first failure does not halt loop.
 * Units/Boundaries:
 *   - PUB001: count is caller-supplied bound selector; arrays use their own lower bounds.
 *   - PUB002: measuringMode 0=linear (bipolar/unipolar), 1=std temp (÷10), 2=climatic (÷100).
 *   - PUB003: Linear scaling uses full-scale raw range; output = loLIM + ratio*(hiLIM-loLIM).
 *   - PUB004: RetVal 16#8001 on invalid measuringMode; 16#8002 on hiLIM<=loLIM.
 *   - PUB005: OutputValue written only on successful conversion; retVal set on error.
 *   - PUB006: Disabled channels (enable=FALSE) are skipped without modifying retVal/outputValue.
 *   - PUB007: All arithmetic uses REAL; explicit conversions applied to raw INT operands.
 *   - PUB008: No delay, no edge detection, no state machine; pure per-scan calculation.
 *)

    tmp_channelsLower := LOWER_BOUND(channels, 1);
    tmp_analogLower   := LOWER_BOUND(analogValues, 1);
    tmp_i := tmp_channelsLower;

    WHILE tmp_i < tmp_channelsLower + count DO
        IF channels[tmp_i].enable THEN
            IF channels[tmp_i].hiLIM <= channels[tmp_i].loLIM THEN
                channels[tmp_i].retVal := 16#8002;
            ELSE
                CASE channels[tmp_i].measuringMode OF
                    0: // Non-temperature linear scaling
                        tmp_raw := analogValues[tmp_analogLower + (tmp_i - tmp_channelsLower)];
                        tmp_analogVal := TO_REAL(tmp_raw);

                        IF channels[tmp_i].bipolar THEN
                            tmp_rawMin := TO_REAL(-27648);
                            tmp_rawMax := TO_REAL(27648);
                        ELSE
                            tmp_rawMin := TO_REAL(0);
                            tmp_rawMax := TO_REAL(27648);
                        END_IF;

                        tmp_rawRange := tmp_rawMax - tmp_rawMin;
                        tmp_engRange := channels[tmp_i].hiLIM - channels[tmp_i].loLIM;

                        channels[tmp_i].outputValue := channels[tmp_i].loLIM + 
                            ((tmp_analogVal - tmp_rawMin) / tmp_rawRange) * tmp_engRange;
                        channels[tmp_i].retVal := 16#0000;

                    1: // Standard temperature
                        tmp_raw := analogValues[tmp_analogLower + (tmp_i - tmp_channelsLower)];
                        channels[tmp_i].outputValue := TO_REAL(tmp_raw) / 10.0;
                        channels[tmp_i].retVal := 16#0000;

                    2: // Climatic temperature
                        tmp_raw := analogValues[tmp_analogLower + (tmp_i - tmp_channelsLower)];
                        channels[tmp_i].outputValue := TO_REAL(tmp_raw) / 100.0;
                        channels[tmp_i].retVal := 16#0000;

                    ELSE
                        channels[tmp_i].retVal := 16#8001;
                END_CASE;
            END_IF;
        END_IF;

        tmp_i := tmp_i + 1;
    END_WHILE;

END_FUNCTION_BLOCK