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
END_TYPE

FUNCTION_BLOCK FB_AnalogBatchProcessing
VAR_INPUT
    count : DINT;
END_VAR
VAR_IN_OUT
    analogValues : ARRAY[*] OF INT;
    channels     : ARRAY[*] OF ST_AnalogChannel;
END_VAR
VAR
    i         : DINT;
    lowerIdx  : DINT;
    upperIdx  : DINT;
    rawValue  : INT;
END_VAR

lowerIdx := LOWER_BOUND(analogValues, 1);
upperIdx := lowerIdx + count - 1;

FOR i := lowerIdx TO upperIdx DO
    rawValue := analogValues[i];
    
    IF channels[i].enable THEN
        CASE channels[i].measuringMode OF
            0: // Non-temperature linear scaling
                IF channels[i].hiLIM > channels[i].loLIM THEN
                    IF channels[i].bipolar THEN
                        channels[i].outputValue := channels[i].loLIM + 
                            ((INT_TO_REAL(rawValue) + 27648.0) / 55296.0) * 
                            (channels[i].hiLIM - channels[i].loLIM);
                    ELSE
                        channels[i].outputValue := channels[i].loLIM + 
                            (INT_TO_REAL(rawValue) / 27648.0) * 
                            (channels[i].hiLIM - channels[i].loLIM);
                    END_IF;
                    channels[i].retVal := 16#0000;
                ELSE
                    channels[i].retVal := 16#8002;
                END_IF;
                
            1: // Standard temperature
                channels[i].outputValue := INT_TO_REAL(rawValue) / 10.0;
                channels[i].retVal := 16#0000;
                
            2: // Climatic temperature
                channels[i].outputValue := INT_TO_REAL(rawValue) / 100.0;
                channels[i].retVal := 16#0000;
                
            ELSE
                channels[i].retVal := 16#8001;
        END_CASE;
    END_IF;
END_FOR;

END_FUNCTION_BLOCK