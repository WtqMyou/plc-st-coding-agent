TYPE ST_Pump :
STRUCT
    priority : INT;
    selection : BOOL;
    RunComd : BOOL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    mode : BOOL;
    start : BOOL;
    stop : BOOL;
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    prioArr : ARRAY[1..5] OF INT;
    idxArr : ARRAY[1..5] OF INT;
    i : INT;
    j : INT;
    tempPrio : INT;
    tempIdx : INT;
END_VAR

    IF stop OR NOT start THEN
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := FALSE;
        END_FOR
    ELSE
        IF NOT mode THEN
            FOR i := 1 TO 5 DO
                pumpGroup[i].RunComd := pumpGroup[i].selection;
            END_FOR
        ELSE
            FOR i := 1 TO 5 DO
                pumpGroup[i].RunComd := FALSE;
            END_FOR

            FOR i := 1 TO 5 DO
                prioArr[i] := pumpGroup[i].priority;
                idxArr[i] := i;
            END_FOR

            FOR i := 1 TO 4 DO
                FOR j := 1 TO 5 - i DO
                    IF (prioArr[j] < prioArr[j + 1]) OR
                       (prioArr[j] = prioArr[j + 1] AND (idxArr[j] > idxArr[j + 1])) THEN
                        tempPrio := prioArr[j];
                        prioArr[j] := prioArr[j + 1];
                        prioArr[j + 1] := tempPrio;
                        tempIdx := idxArr[j];
                        idxArr[j] := idxArr[j + 1];
                        idxArr[j + 1] := tempIdx;
                    END_IF
                END_FOR
            END_FOR

            FOR i := 1 TO 3 DO
                pumpGroup[idxArr[i]].RunComd := TRUE;
            END_FOR
        END_IF
    END_IF

END_FUNCTION_BLOCK