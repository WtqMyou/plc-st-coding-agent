TYPE ST_Pump : STRUCT
    priority : INT;
    selection : BOOL;
    runCmd   : BOOL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK FB_MultiPumpControl
VAR_INPUT
    mode  : BOOL;
    start : BOOL;
    stop  : BOOL;
END_VAR

VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR

VAR
    lastStart : BOOL := FALSE;
    lastStop  : BOOL := FALSE;
    edgeStart : BOOL;
    edgeStop  : BOOL;
    i         : INT;
    j         : INT;
    tempPump  : ST_Pump;
    pumpSorted : ARRAY[1..5] OF ST_Pump;
END_VAR

edgeStart := start AND NOT lastStart;
edgeStop  := stop  AND NOT lastStop;
lastStart := start;
lastStop  := stop;

IF edgeStop THEN
    FOR i := 1 TO 5 DO
        pumpGroup[i].runCmd := FALSE;
    END_FOR;
END_IF;

IF edgeStart THEN
    IF mode = FALSE THEN
        FOR i := 1 TO 5 DO
            pumpGroup[i].runCmd := pumpGroup[i].selection;
        END_FOR;
    ELSE
        pumpSorted := pumpGroup;
        FOR i := 1 TO 4 DO
            FOR j := 1 TO 5 - i DO
                IF pumpSorted[j].priority < pumpSorted[j + 1].priority THEN
                    tempPump := pumpSorted[j];
                    pumpSorted[j] := pumpSorted[j + 1];
                    pumpSorted[j + 1] := tempPump;
                END_IF;
            END_FOR;
        END_FOR;
        pumpSorted[1].runCmd := TRUE;
        pumpSorted[2].runCmd := TRUE;
        pumpSorted[3].runCmd := TRUE;
        pumpSorted[4].runCmd := FALSE;
        pumpSorted[5].runCmd := FALSE;
        pumpGroup := pumpSorted;
    END_IF;
END_IF;

END_FUNCTION_BLOCK