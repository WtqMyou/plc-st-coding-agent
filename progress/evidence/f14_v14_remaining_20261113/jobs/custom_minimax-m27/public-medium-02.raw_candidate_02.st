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
END_VAR

(*
ENGINEERING_CONTRACT
================================================================================
PUB001: Process 'count' channels starting at each array's lower bound.
        Arrays passed by reference preserve caller-defined bounds.
        Read-only: analogValues elements are never modified.
PUB002: Per-channel conversion based on measuringMode field.
        - Mode 0: Linear scaling using hiLIM/loLIM and bipolar flag.
        - Mode 1: Standard temperature (raw / 10.0).
        - Mode 2: Climatic temperature (raw / 100.0).
        - Invalid mode: retVal=16#8001, outputValue unchanged.
PUB003: Mode 0 linear scaling maps raw 0..27648 (unipolar) or -27648..27648 (bipolar)
        to loLIM..hiLIM range. OutputValue = loLIM + (raw - rawMin) * (hiLIM - loLIM) / range.
PUB004: If hiLIM <= loLIM in mode 0, set retVal=16#8002 and skip conversion.
PUB005: Disabled channels (enable=FALSE) are skipped; retVal and outputValue unchanged.
PUB006: Per-channel retVal WORD status: 16#8001 (invalid mode), 16#8002 (bad range).
PUB007: Same-scan priority: enable→measuringMode→hiLIM/loLIM check→conversion.
PUB008: Temperature output = raw / divisor (10 or 100) as REAL.
--------------------------------------------------------------------------------
*)

VAR
    tmpIndex     : DINT;
    tmpRaw       : INT;
    tmpRawReal   : REAL;
    tmpRange     : REAL;
    tmpOffset    : REAL;
    tmpChannel   : ST_AnalogChannel;
    tmpLower     : DINT;
    tmpUpperAna  : DINT;
    tmpUpperCh   : DINT;
    tmpProcessed : BOOL;
END_VAR

(* CONTRACT_RULES [] *)

tmpLower    := LOWER_BOUND(analogValues, 1);
tmpUpperAna := UPPER_BOUND(analogValues, 1);
tmpUpperCh  := UPPER_BOUND(channels, 1);

FOR tmpIndex := 0 TO (count - 1) DO
    tmpProcessed := FALSE;

    (* Bounds check: skip if index exceeds either array *)
    IF (tmpLower + tmpIndex) <= tmpUpperAna AND (tmpLower + tmpIndex) <= tmpUpperCh THEN
        tmpChannel := channels[tmpLower + tmpIndex];

        (* Skip disabled channels; retain previous outputValue and retVal *)
        IF tmpChannel.enable THEN

    (* Determine conversion based on measuringMode *)
    IF tmpChannel.measuringMode = 0 THEN
        (* Non-temperature linear scaling *)
        IF tmpChannel.hiLIM <= tmpChannel.loLIM THEN
            channels[tmpLower + tmpIndex].retVal := 16#8002;
        ELSE
            tmpRaw       := analogValues[tmpLower + tmpIndex];
            tmpRawReal   := TO_REAL(tmpRaw);
            tmpRange     := tmpChannel.hiLIM - tmpChannel.loLIM;

            IF tmpChannel.bipolar THEN
                (* Map -27648..27648 to loLIM..hiLIM *)
                tmpOffset    := TO_REAL(27648);
                channels[tmpLower + tmpIndex].outputValue := tmpChannel.loLIM + 
                    (tmpRawReal + tmpOffset) * tmpRange / TO_REAL(55296);
            ELSE
                (* Map 0..27648 to loLIM..hiLIM *)
                channels[tmpLower + tmpIndex].outputValue := tmpChannel.loLIM + 
                    tmpRawReal * tmpRange / TO_REAL(27648);
            END_IF;
            channels[tmpLower + tmpIndex].retVal := 0;
        END_IF;
        tmpProcessed := TRUE;
    ELSIF tmpChannel.measuringMode = 1 THEN
        (* Standard temperature: outputValue = raw / 10 *)
        tmpRaw := analogValues[tmpLower + tmpIndex];
        channels[tmpLower + tmpIndex].outputValue := TO_REAL(tmpRaw) / TO_REAL(10);
        channels[tmpLower + tmpIndex].retVal := 0;
        tmpProcessed := TRUE;
    ELSIF tmpChannel.measuringMode = 2 THEN
        (* Climatic temperature: outputValue = raw / 100 *)
        tmpRaw := analogValues[tmpLower + tmpIndex];
        channels[tmpLower + tmpIndex].outputValue := TO_REAL(tmpRaw) / TO_REAL(100);
        channels[tmpLower + tmpIndex].retVal := 0;
        tmpProcessed := TRUE;
    END_IF;

    (* Invalid measuringMode (not 0, 1, or 2) *)
    IF NOT tmpProcessed THEN
        channels[tmpLower + tmpIndex].retVal := 16#8001;
    END_IF;

END_FOR;

END_FUNCTION_BLOCK