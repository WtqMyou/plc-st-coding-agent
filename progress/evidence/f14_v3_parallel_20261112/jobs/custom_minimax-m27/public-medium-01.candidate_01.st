FUNCTION_BLOCK FB_MultiPumpControl
VAR_INPUT
    mode  : BOOL;    // FALSE: Manual, TRUE: Automatic
    start : BOOL;    // Start button
    stop  : BOOL;    // Stop button
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
    tempPri   : INT;
    tempSel   : BOOL;
    tempCmd   : BOOL;
    sorted    : ARRAY[1..5] OF ST_Pump;
END_VAR

// Edge detection for rising edges
edgeStart := start AND NOT lastStart;
edgeStop  := stop  AND NOT lastStop;
lastStart := start;
lastStop  := stop;

// Stop all pumps when stop button is pressed
IF edgeStop THEN
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR;
END_IF;

// Start selected pumps when start button is pressed
IF edgeStart THEN
    IF mode = FALSE THEN
        // Manual mode: run pumps where selection = TRUE
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := pumpGroup[i].selection;
        END_FOR;
    ELSE
        // Automatic mode: three pumps in use, two on standby
        // Sort pumps by priority (descending) using bubble sort
        sorted := pumpGroup;
        FOR i := 1 TO 4 DO
            FOR j := 1 TO 5 - i DO
                IF sorted[j].priority < sorted[j + 1].priority THEN
                    tempPri := sorted[j].priority;
                    tempSel := sorted[j].selection;
                    tempCmd := sorted[j].RunComd;
                    sorted[j].priority   := sorted[j + 1].priority;
                    sorted[j].selection  := sorted[j + 1].selection;
                    sorted[j].RunComd    := sorted[j + 1].RunComd;
                    sorted[j + 1].priority := tempPri;
                    sorted[j + 1].selection := tempSel;
                    sorted[j + 1].RunComd   := tempCmd;
                END_IF;
            END_FOR;
        END_FOR;
        // Top 3 highest priority pumps run
        sorted[1].RunComd := TRUE;
        sorted[2].RunComd := TRUE;
        sorted[3].RunComd := TRUE;
        sorted[4].RunComd := FALSE;
        sorted[5].RunComd := FALSE;
        // Copy RunComd back to original array (preserving original order)
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := sorted[i].RunComd;
        END_FOR;
    END_IF;
END_IF;

END_FUNCTION_BLOCK