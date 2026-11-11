TYPE ST_Pump :
STRUCT
    priority  : INT;
    selection : BOOL;
    RunComd   : BOOL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_MultiPumpControl
VAR_INPUT
    mode  : BOOL; // FALSE: Manual, TRUE: Automatic
    start : BOOL; // Start selected pumps
    stop  : BOOL; // Stop all pumps
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    runActive   : BOOL := FALSE;
    selected    : ARRAY[1..5] OF BOOL;
    i           : INT;
    rank        : INT;
    bestIndex   : INT;
    bestPriority: INT;
END_VAR

IF stop THEN
    runActive := FALSE;
ELSIF start THEN
    runActive := TRUE;
END_IF;

FOR i := 1 TO 5 DO
    selected[i] := FALSE;
END_FOR;

IF runActive THEN
    IF mode THEN
        FOR rank := 1 TO 3 DO
            bestIndex := 0;
            bestPriority := 0;

            FOR i := 1 TO 5 DO
                IF NOT selected[i] THEN
                    IF (bestIndex = 0) OR (pumpGroup[i].priority > bestPriority) THEN
                        bestIndex := i;
                        bestPriority := pumpGroup[i].priority;
                    END_IF;
                END_IF;
            END_FOR;

            IF bestIndex <> 0 THEN
                selected[bestIndex] := TRUE;
            END_IF;
        END_FOR;
    ELSE
        FOR i := 1 TO 5 DO
            selected[i] := pumpGroup[i].selection;
        END_FOR;
    END_IF;
END_IF;

FOR i := 1 TO 5 DO
    pumpGroup[i].RunComd := selected[i] AND runActive;
END_FOR;