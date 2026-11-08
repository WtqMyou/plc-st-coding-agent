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
    i : INT;
    pass : INT;
    bestIdx : INT;
    maxP : INT;
    selected : ARRAY[1..5] OF BOOL;
END_VAR

FOR i := 1 TO 5 DO
    selected[i] := FALSE;
END_FOR

IF mode AND start AND NOT stop THEN
    FOR pass := 1 TO 3 DO
        bestIdx := 0;
        maxP := -32768;
        FOR i := 1 TO 5 DO
            IF NOT selected[i] THEN
                IF bestIdx = 0 THEN
                    bestIdx := i;
                    maxP := pumpGroup[i].priority;
                ELSIF pumpGroup[i].priority > maxP THEN
                    bestIdx := i;
                    maxP := pumpGroup[i].priority;
                END_IF
            END_IF
        END_FOR
        IF bestIdx <> 0 THEN
            selected[bestIdx] := TRUE;
        END_IF
    END_FOR
END_IF

FOR i := 1 TO 5 DO
    IF stop THEN
        pumpGroup[i].RunComd := FALSE;
    ELSIF NOT start THEN
        pumpGroup[i].RunComd := FALSE;
    ELSIF mode THEN
        pumpGroup[i].RunComd := selected[i];
    ELSE
        pumpGroup[i].RunComd := pumpGroup[i].selection;
    END_IF
END_FOR

END_FUNCTION_BLOCK