TYPE ST_Pump :
STRUCT
    priority  : INT;
    selection : BOOL;
    RunComd   : BOOL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    mode  : BOOL;   // FALSE = Manual, TRUE = Automatic
    start : BOOL;   // Start button
    stop  : BOOL;   // Stop button (highest priority)
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    sortedIndices : ARRAY[1..5] OF INT;
    i, j, temp    : INT;
END_VAR

    // Stop has the highest priority – all pumps off when stop is active
    IF stop THEN
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := FALSE;
        END_FOR
    ELSE
        // Start must be active to issue any run commands
        IF start THEN
            IF mode THEN
                // ----- Automatic mode: select the three pumps with highest priority -----
                // Initialise index list
                sortedIndices[1] := 1;
                sortedIndices[2] := 2;
                sortedIndices[3] := 3;
                sortedIndices[4] := 4;
                sortedIndices[5] := 5;

                // Bubble‑sort descending by priority; equal priority → lower index first
                FOR i := 1 TO 4 DO
                    FOR j := i+1 TO 5 DO
                        IF pumpGroup[sortedIndices[j]].priority > pumpGroup[sortedIndices[i]].priority OR
                           (pumpGroup[sortedIndices[j]].priority = pumpGroup[sortedIndices[i]].priority AND
                            sortedIndices[j] < sortedIndices[i]) THEN
                            temp := sortedIndices[i];
                            sortedIndices[i] := sortedIndices[j];
                            sortedIndices[j] := temp;
                        END_IF
                    END_FOR
                END_FOR

                // Command the three highest‑priority pumps to run
                FOR i := 1 TO 5 DO
                    IF i <= 3 THEN
                        pumpGroup[sortedIndices[i]].RunComd := TRUE;
                    ELSE
                        pumpGroup[sortedIndices[i]].RunComd := FALSE;
                    END_IF
                END_FOR
            ELSE
                // ----- Manual mode: run pumps according to user selection -----
                FOR i := 1 TO 5 DO
                    pumpGroup[i].RunComd := pumpGroup[i].selection;
                END_FOR
            END_IF
        ELSE
            // start = FALSE → no pump may run
            FOR i := 1 TO 5 DO
                pumpGroup[i].RunComd := FALSE;
            END_FOR
        END_IF
    END_IF
END_FUNCTION_BLOCK