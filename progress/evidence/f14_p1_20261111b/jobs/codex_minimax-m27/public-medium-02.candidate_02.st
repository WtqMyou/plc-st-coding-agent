FUNCTION_BLOCK FB_AnalogBatchProcess
VAR_INPUT
    count : DINT;
END_VAR

VAR_IN_OUT
    analogValues : ARRAY[*] OF INT;
    channels     : ARRAY[*] OF ST_AnalogChannel;
END_VAR

VAR
    i           : DINT;
    idx         : DINT;
    rawValue    : INT;
    validInput  : BOOL;
END_VAR

i := 0;
WHILE i < count DO
    idx := LOWER_BOUND(channels, 1) + i;
    
    // Check if channel is enabled
    IF channels[idx].enable THEN
        // Default success status
        channels[idx].retVal := 16#0000;
        
        // Validate hiLIM > loLIM
        IF channels[idx].hiLIM > channels[idx].loLIM THEN
            // Get raw analog value
            rawValue := analogValues[LOWER_BOUND(analogValues, 1) + i];
            
            // Perform conversion based on measuringMode
            CASE channels[idx].measuringMode OF
                0: // Non-temperature linear scaling
                    IF channels[idx].bipolar THEN
                        // Bipolar: map -27648..27648 to loLIM..hiLIM
                        channels[idx].outputValue := (INT_TO_REAL(rawValue) + 27648.0) / 55296.0 * (channels[idx].hiLIM - channels[idx].loLIM) + channels[idx].loLIM;
                    ELSE
                        // Unipolar: map 0..27648 to loLIM..hiLIM
                        channels[idx].outputValue := INT_TO_REAL(rawValue) / 27648.0 * (channels[idx].hiLIM - channels[idx].loLIM) + channels[idx].loLIM;
                    END_IF;
                    
                1: // Standard temperature: outputValue = raw / 10
                    channels[idx].outputValue := INT_TO_REAL(rawValue) / 10.0;
                    
                2: // Climatic temperature: outputValue = raw / 100
                    channels[idx].outputValue := INT_TO_REAL(rawValue) / 100.0;
                    
            ELSE
                // Invalid measuringMode
                channels[idx].retVal := 16#8001;
            END_CASE;
        ELSE
            // hiLIM <= loLIM error
            channels[idx].retVal := 16#8002;
        END_IF;
    END_IF;
    
    i := i + 1;
END_WHILE;

END_FUNCTION_BLOCK