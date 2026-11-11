(*--------------------------------------------------------------
  Type definition for a single analog channel.
--------------------------------------------------------------*)
TYPE ST_AnalogChannel
STRUCT
    enable        : BOOL;      (* Channel conversion enable *)
    hiLIM         : REAL;      (* Upper engineering‑unit limit *)
    loLIM         : REAL;      (* Lower engineering‑unit limit *)
    bipolar       : BOOL;      (* FALSE → unipolar, TRUE → bipolar *)
    measuringMode : INT;       (* 0 = linear, 1 = std temp, 2 = climatic *)
    retVal        : WORD;      (* Per‑channel status code (output) *)
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
    analogValues : ARRAY[*] OF INT;    (* Raw analog values (read‑only) *)
    channels     : ARRAY[*] OF ST_AnalogChannel; (* Channel settings & results *)
END_VAR
VAR
    i          : DINT;
    idxA       : INT;
    idxC       : INT;
    lowerA     : INT;
    lowerC     : INT;
    rawValue   : INT;
    rawMin     : REAL;
    rawMax     : REAL;
    scale      : REAL;
    ch         : ST_AnalogChannel;
END_VAR

    (* Determine the lower bounds of the variable‑length arrays *)
    lowerA := LOWER_BOUND(analogValues, 1);
    lowerC := LOWER_BOUND(channels, 1);

    FOR i := 0 TO count - 1 DO
        idxA := lowerA + INT#(i);
        idxC := lowerC + INT#(i);

        (* Read the channel configuration (read‑only) *)
        ch := channels[idxC];

        (* If the channel is disabled, just clear its outputs *)
        IF NOT ch.enable THEN
            channels[idxC].retVal      := 16#0000;   (* No error *)
            channels[idxC].outputValue := 0.0;
            CONTINUE;
        END_IF

        (* Read the raw analog value (read‑only) *)
        rawValue := analogValues[idxA];

        (* Branch according to measuring mode *)
        CASE ch.measuringMode OF
            0: (* ---- Non‑temperature linear scaling ---- *)
                (* Check that hiLIM > loLIM *)
                IF ch.hiLIM <= ch.loLIM THEN
                    channels[idxC].retVal      := 16#8002;  (* Range error *)
                    channels[idxC].outputValue := 0.0;
                ELSE
                    (* Determine the raw value range *)
                    IF ch.bipolar THEN
                        rawMin := -27648.0;
                        rawMax :=  27648.0;
                    ELSE
                        rawMin := 0.0;
                        rawMax := 27648.0;
                    END_IF

                    (* Linear conversion *)
                    scale := (ch.hiLIM - ch.loLIM) / (rawMax - rawMin);
                    channels[idxC].outputValue := ch.loLIM
                                 + (INT_TO_REAL(rawValue) - rawMin) * scale;
                    channels[idxC].retVal := 16#0000;      (* Success *)
                END_IF

            1: (* ---- Standard‑temperature conversion ---- *)
                channels[idxC].outputValue := INT_TO_REAL(rawValue) / 10.0;
                channels[idxC].retVal      := 16#0000;

            2: (* ---- Climatic‑temperature conversion ---- *)
                channels[idxC].outputValue := INT_TO_REAL(rawValue) / 100.0;
                channels[idxC].retVal      := 16#0000;

            ELSE
                (* Unknown measuring mode *)
                channels[idxC].retVal      := 16#8001;  (* Invalid mode *)
                channels[idxC].outputValue := 0.0;
        END_CASE

    END_FOR
END_FUNCTION_BLOCK