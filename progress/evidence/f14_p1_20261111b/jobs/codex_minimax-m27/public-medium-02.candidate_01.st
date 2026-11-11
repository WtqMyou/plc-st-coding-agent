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
    channel     : REF_TO ST_AnalogChannel;
END_VAR

// Process each channel by ordinal position
FOR i := 0 TO count - 1 DO
    idx := LOWER_BOUND(channels, 1) + i;
    channel := REF(channels[idx]);
    
    // Skip disabled channels
    IF NOT channel.enable THEN
        CONTINUE;
    END_IF
    
    // Default success status
    channel.retVal := 16#0000;
    
    // Validate hiLIM > loLIM
    IF channel.hiLIM <= channel.loLIM THEN
        channel.retVal := 16#8002;
        CONTINUE;
    END_IF
    
    // Get raw analog value (read-only)
    rawValue := analogValues[LOWER_BOUND(analogValues, 1) + i];
    
    // Perform conversion based on measuringMode
    CASE channel.measuringMode OF
        0: // Non-temperature linear scaling
            IF channel.bipolar THEN
                // Bipolar: map -27648..27648 to loLIM..hiLIM
                channel.outputValue := (INT_TO_REAL(rawValue) + 27648.0) / 55296.0 * (channel.hiLIM - channel.loLIM) + channel.loLIM;
            ELSE
                // Unipolar: map 0..27648 to loLIM..hiLIM
                channel.outputValue := INT_TO_REAL(rawValue) / 27648.0 * (channel.hiLIM - channel.loLIM) + channel.loLIM;
            END_IF;
            
        1: // Standard temperature: outputValue = raw / 10
            channel.outputValue := INT_TO_REAL(rawValue) / 10.0;
            
        2: // Climatic temperature: outputValue = raw / 100
            channel.outputValue := INT_TO_REAL(rawValue) / 100.0;
            
    ELSE
        // Invalid measuringMode
        channel.retVal := 16#8001;
    END_CASE;
END_FOR;

END_FUNCTION_BLOCK