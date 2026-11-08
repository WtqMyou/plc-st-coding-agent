TYPE ST_Pump
    STRUCT
        priority   : INT;
        selection  : BOOL;
        RunComd    : BOOL;
    END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    mode  : BOOL;
    start : BOOL;
    stop  : BOOL;
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    prevStart     : BOOL := FALSE;
    prevStop      : BOOL := FALSE;
    i             : INT;
    j             : INT;
    k             : INT;
    tmp           : INT;
    tmpIdx        : INT;
    tempPriority  : ARRAY[1..5] OF INT;
    sortedIdx     : ARRAY[1..5] OF INT;
END_VAR

IF stop THEN
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR;
ELSE
    IF start AND NOT prevStart THEN
        IF NOT mode THEN
            FOR i := 1 TO 5 DO
                IF pumpGroup[i].selection THEN
                    pumpGroup[i].RunComd := TRUE;
                ELSE
                    pumpGroup[i].RunComd := FALSE;
                END_IF;
            END_FOR;
        ELSE
            FOR i := 1 TO 5 DO
                tempPriority[i] := pumpGroup[i].priority;
                sortedIdx[i] := i;
            END_FOR;
            FOR j := 1 TO 4 DO
                FOR k := j + 1 TO 5 DO
                    IF tempPriority[k] > tempPriority[j] OR
                       (tempPriority[k] = tempPriority[j] AND sortedIdx[k] < sortedIdx[j]) THEN
                        tmp := tempPriority[j];
                        tempPriority[j] := tempPriority[k];
                        tempPriority[k] := tmp;
                        tmpIdx := sortedIdx[j];
                        sortedIdx[j] := sortedIdx[k];
                        sortedIdx[k] := tmpIdx;
                    END_IF;
                END_FOR;
            END_FOR;
            FOR i := 1 TO 5 DO
                IF i <= 3 THEN
                    pumpGroup[sortedIdx[i]].RunComd := TRUE;
                ELSE
                    pumpGroup[sortedIdx[i]].RunComd := FALSE;
                END_IF;
            END_FOR;
        END_IF;
    ELSE
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := FALSE;
        END_FOR;
    END_IF;
END_IF;

prevStart := start;
prevStop := stop;

END_FUNCTION_BLOCK