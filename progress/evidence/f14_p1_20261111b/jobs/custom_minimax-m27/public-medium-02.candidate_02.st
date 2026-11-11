(*--------------------------------------------------------------
  Type definition for a single analog channel.
--------------------------------------------------------------*)
TYPE ST_AnalogChannel
STRUCT
    enable        : BOOL;      (* Channel conversion enable *)
    hiLIM         : REAL;      (* Upper engineering-unit limit *)
    loLIM         : REAL;      (* Lower engineering-unit limit *)
    bipolar       : BOOL;      (* FALSE → unipolar, TRUE → bipolar *)
    measuringMode : INT;       (* 0 = linear, 1 = std temp, 2 = climatic *)
    retVal        : WORD;      (* Per-channel status code (output) *)
    outputValue   : REAL;      (* Converted engineering value (output) *)
END_STRUCT
END_TYPE

(*--------------------------------------------------------------
  Function block: FB_AnalogBatchProcessing
  Processes up to *count* analog channels.
--------------------------------------------------------------*)
FUNCTION_BLOCK FB_AnalogBatchProcessing
VAR_INPUT
    count : DINT;                      (* Number of channels to process *)
END_VAR
VAR_IN_OUT
    analogValues : ARRAY[*] OF INT;    (* Raw analog values (read-only) *)
    channels     : ARRAY[*] OF ST_AnalogChannel; (* Channel settings & results *)
END_VAR
VAR
    i          : DINT;
    rawValue   : INT;
    rawMin     : REAL;
    rawMax     : REAL;
    scale      : REAL;
    ch         : ST_AnalogChannel;
END_VAR

    FOR i := 0 TO count - 1 DO
        rawValue := analogValues[LOWER_BOUND(analogValues, 1) + i];
        ch := channels[LOWER_BOUND(channels, 1) + i];

        IF NOT ch.enable THEN
            channels[LOWER_BOUND(channels, 1) + i].retVal      := 16#0000;
            channels[LOWER_BOUND(channels, 1) + i].outputValue := 0.0;
        ELSE
            CASE ch.measuringMode OF
                0: (* ---- Non-temperature linear scaling ---- *)
                    IF ch.hiLIM <= ch.loLIM THEN
                        channels[LOWER_BOUND(channels, 1) + i].retVal      := 16#8002;
                        channels[LOWER_BOUND(channels, 1) + i].outputValue := 0.0;
                    ELSE
                        IF ch.bipolar THEN
                            rawMin := -27648.0;
                            rawMax :=  27648.0;
                        ELSE
                            rawMin := 0.0;
                            rawMax := 27648.0;
                        END_IF
                        scale := (ch.hiLIM - ch.loLIM) / (rawMax - rawMin);
                        channels[LOWER_BOUND(channels, 1) + i].outputValue := ch.loLIM
                                     + (INT_TO_REAL(rawValue) - rawMin) * scale;
                        channels[LOWER_BOUND(channels, 1) + i].retVal := 16#0000;
                    END_IF

                1: (* ---- Standard-temperature conversion ---- *)
                    channels[LOWER_BOUND(channels, 1) + i].outputValue := INT_TO_REAL(rawValue) / 10.0;
                    channels[LOWER_BOUND(channels, 1) + i].retVal      := 16#0000;

                2: (* ---- Climatic-temperature conversion ---- *)
                    channels[LOWER_BOUND(channels, 1) + i].outputValue := INT_TO_REAL(rawValue) / 100.0;
                    channels[LOWER_BOUND(channels, 1) + i].retVal      := 16#0000;

                ELSE
                    channels[LOWER_BOUND(channels, 1) + i].retVal      := 16#8001;
                    channels[LOWER_BOUND(channels, 1) + i].outputValue := 0.0;
            END_CASE
        END_IF
    END_FOR
END_FUNCTION_BLOCK