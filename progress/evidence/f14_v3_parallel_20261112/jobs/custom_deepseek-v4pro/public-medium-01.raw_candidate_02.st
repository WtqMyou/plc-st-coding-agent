TYPE ST_Pump :
STRUCT
    priority : INT;
    selection : BOOL;
    RunComd : BOOL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_MultiPumpControl
VAR_INPUT
    mode : BOOL;
    start : BOOL;
    stop : BOOL;
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    runActive : BOOL := FALSE;
    autoSelected : ARRAY[1..5] OF BOOL;
    i : INT;
    j : INT;
    rank : INT;
END_VAR

IF stop THEN
    runActive := FALSE;
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR;
ELSE
    IF start THEN
        runActive := TRUE;
    END_IF;

    IF runActive THEN
        IF mode THEN
            FOR i := 1 TO 5 DO
                rank := 0;
                FOR j := 1 TO 5 DO
                    IF (pumpGroup[j].priority > pumpGroup[i].priority) OR
                       ((pumpGroup[j].priority = pumpGroup[i].priority) AND (j < i)) THEN
                        rank := rank + 1;
                    END_IF;
                END_FOR;
                autoSelected[i] := (rank < 3);
            END_FOR;

            FOR i := 1 TO 5 DO
                pumpGroup[i].RunComd := autoSelected[i];
            END_FOR;
        ELSE
            FOR i := 1 TO 5 DO
                pumpGroup[i].RunComd := pumpGroup[i].selection;
            END_FOR;
        END_IF;
    ELSE
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := FALSE;
        END_FOR;
    END_IF;
END_IF;

END_FUNCTION_BLOCK