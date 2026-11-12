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
    loLIM : REAL;
    hiLIM : REAL;
END_VAR

loLIM := 0.0;
hiLIM := 0.0;

FOR i := 0 TO count - 1 DO
    idx := LOWER_BOUND(analogValues, 1) + i;
    rawValue := analogValues[idx];
    
    channels[idx].retVal := 16#0000;
    
    IF channels[idx].enable THEN
        loLIM := channels[idx].loLIM;
        hiLIM := channels[idx].hiLIM;
        
        CASE channels[idx].measuringMode OF
            0: // Non-temperature linear scaling
                IF hiLIM > loLIM THEN
                    IF channels[idx].bipolar THEN
                        rawMin := -27648;
                        rawMax := 27648;
                    ELSE
                        rawMin := 0;
                        rawMax := 27648;
                    END_IF;
                    
                    channels[idx].outputValue := TO_REAL(rawValue - rawMin) / TO_REAL(rawMax - rawMin) * (hiLIM - loLIM) + loLIM;
                ELSE
                    channels[idx].retVal := 16#8002;
                END_IF;
                
            1: // Standard temperature: outputValue = raw / 10
                channels[idx].outputValue := TO_REAL(rawValue) / 10.0;
                
            2: // Climatic temperature: outputValue = raw / 100
                channels[idx].outputValue := TO_REAL(rawValue) / 100.0;
                
            ELSE
                channels[idx].retVal := 16#8001;
        END_CASE;
    END_IF;
END_FOR;
END_FUNCTION_BLOCK