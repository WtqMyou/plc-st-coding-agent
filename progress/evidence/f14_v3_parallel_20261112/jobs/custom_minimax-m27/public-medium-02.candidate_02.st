TYPE ST_AnalogChannel :
STRUCT
    enable : BOOL;
    hiLIM : REAL;
    loLIM : REAL;
    bipolar : BOOL;
    measuringMode : INT;
    retVal : WORD;
    outputValue : REAL;
END_STRUCT;
END_TYPE;

FUNCTION_BLOCK FB_AnalogBatchProcessing
VAR_INPUT
    count : DINT;
END_VAR

VAR_IN_OUT
    analogValues : ARRAY[*] OF INT;
    channels : ARRAY[*] OF ST_AnalogChannel;
END_VAR

VAR
    i : DINT;
    idx : DINT;
    rawValue : INT;
    rawMin : INT;
    rawMax : INT;
    chLoLIM : REAL;
    chHiLIM : REAL;
    ch : REFERENCE TO ST_AnalogChannel;
END_VAR

FOR i := 0 TO count - 1 DO
    idx := LOWER_BOUND(analogValues, 1) + i;
    rawValue := analogValues[idx];
    ch REF= channels[idx];
    ch.retVal := 16#0000;
    
    IF ch.enable THEN
        chLoLIM := ch.loLIM;
        chHiLIM := ch.hiLIM;
        
        CASE ch.measuringMode OF
            0:
                IF chHiLIM > chLoLIM THEN
                    IF ch.bipolar THEN
                        rawMin := -27648;
                        rawMax := 27648;
                    ELSE
                        rawMin := 0;
                        rawMax := 27648;
                    END_IF;
                    ch.outputValue := INT_TO_REAL(rawValue - rawMin) / INT_TO_REAL(rawMax - rawMin) * (chHiLIM - chLoLIM) + chLoLIM;
                ELSE
                    ch.retVal := 16#8002;
                END_IF;
                
            1:
                ch.outputValue := INT_TO_REAL(rawValue) / 10.0;
                
            2:
                ch.outputValue := INT_TO_REAL(rawValue) / 100.0;
                
            ELSE
                ch.retVal := 16#8001;
        END_CASE;
    END_IF;
END_FOR;
END_FUNCTION_BLOCK