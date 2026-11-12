TYPE ST_Pump :
STRUCT
    priority : INT;
    selection : BOOL;
    RunComd : BOOL;
END_STRUCT;
END_TYPE;

FUNCTION_BLOCK MultiPumpSwitchingControl
VAR_INPUT
    mode : BOOL;
    start : BOOL;
    stop : BOOL;
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    runActive : BOOL;
    rank : ARRAY[1..5] OF INT;
    i : INT;
    j : INT;
END_VAR

IF stop THEN
    runActive := FALSE;
ELSIF start THEN
    runActive := TRUE;
END_IF;

IF runActive THEN
    IF mode THEN
        FOR i := 1 TO 5 DO
            rank[i] := 1;
            FOR j := 1 TO 5 DO
                IF pumpGroup[j].priority > pumpGroup[i].priority THEN
                    rank[i] := rank[i] + 1;
                ELSIF (pumpGroup[j].priority = pumpGroup[i].priority) AND (j < i) THEN
                    rank[i] := rank[i] + 1;
                END_IF;
            END_FOR;
        END_FOR;

        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := rank[i] <= 3;
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

END_FUNCTION_BLOCK