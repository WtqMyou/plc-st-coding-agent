FUNCTION_BLOCK FB_MultiPumpControl
VAR_INPUT
    mode    : BOOL;  // FALSE: Manual mode, TRUE: Automatic mode
    start   : BOOL;  // Start button
    stop    : BOOL;  // Stop button
END_VAR

VAR_IN_OUT
    pumpGroup   : ARRAY[1..5] OF ST_Pump;
END_VAR

VAR
    startOld    : BOOL := FALSE;
    stopOld     : BOOL := FALSE;
    startEdge   : BOOL;
    stopEdge    : BOOL;
    i           : INT;
    runCount    : INT;
    tempPump    : ST_Pump;
    sorted      : BOOL := FALSE;
    priorities  : ARRAY[1..5] OF INT;
END_VAR

// Detect rising edges
startEdge := start AND NOT startOld;
stopEdge  := stop  AND NOT stopOld;
startOld  := start;
stopOld   := stop;

// Stop all pumps when stop is pressed
IF stopEdge THEN
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR
    sorted := FALSE;
    RETURN;
END_IF

// Start pumps when start is pressed
IF startEdge THEN
    IF mode = FALSE THEN
        // Manual mode: start pumps based on selection
        FOR i := 1 TO 5 DO
            IF pumpGroup[i].selection THEN
                pumpGroup[i].RunComd := TRUE;
            END_IF
        END_FOR
    ELSE
        // Automatic mode: select top 3 by priority (bubble sort)
        // Store priorities
        FOR i := 1 TO 5 DO
            priorities[i] := pumpGroup[i].priority;
        END_FOR
        
        // Bubble sort priorities and rearrange pumpGroup accordingly
        FOR i := 1 TO 5 DO
            tempPump := pumpGroup[i];
        END_FOR
        
        // Sort by priority descending
        FOR i := 1 TO 4 DO
            IF priorities[i] < priorities[i+1] THEN
                // Swap priorities
                tempPump := pumpGroup[i];
                pumpGroup[i] := pumpGroup[i+1];
                pumpGroup[i+1] := tempPump;
                
                // Update priority array
                priorities[i] := pumpGroup[i].priority;
                priorities[i+1] := pumpGroup[i+1].priority;
            END_IF
        END_FOR
        
        // Select top 3 pumps
        runCount := 0;
        FOR i := 1 TO 5 DO
            IF runCount < 3 THEN
                pumpGroup[i].RunComd := TRUE;
                runCount := runCount + 1;
            ELSE
                pumpGroup[i].RunComd := FALSE;
            END_IF
        END_FOR
        
        sorted := TRUE;
    END_IF
END_IF
END_FUNCTION_BLOCK