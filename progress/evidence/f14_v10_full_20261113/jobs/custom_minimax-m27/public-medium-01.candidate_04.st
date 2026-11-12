FUNCTION_BLOCK FB_MultiPumpControl
VAR_INPUT
    mode  : BOOL;  // FALSE=Manual, TRUE=Automatic
    start : BOOL;
    stop  : BOOL;
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    startPrev : BOOL;
    stopPrev  : BOOL;
    i         : INT;
    j         : INT;
    tmpPumpCount : INT;
    tmpPriorities : ARRAY[1..5] OF INT;
    tmpIndices    : ARRAY[1..5] OF INT;
    tmpSelectedIdx : ARRAY[1..3] OF INT;
    tmpSelectedCount : INT;
    tmpMaxIdx  : INT;
    tmpMaxVal  : INT;
    tmpSwap    : INT;
    tmpSel     : BOOL;
END_VAR

// Manual edge detection for start and stop
IF stop AND NOT stopPrev THEN
    // Rising edge on stop - stops all pumps immediately
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR;
    stopPrev := stop;
    startPrev := start;
    RETURN;
END_IF;
stopPrev := stop;

IF start AND NOT startPrev THEN
    // Rising edge on start
    IF mode = FALSE THEN
        // Manual mode: start pumps where selection=TRUE
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := pumpGroup[i].selection;
        END_FOR;
    ELSE
        // Automatic mode: select top 3 pumps by priority
        tmpPumpCount := 0;
        FOR i := 1 TO 5 DO
            IF pumpGroup[i].priority > 0 THEN
                tmpPumpCount := tmpPumpCount + 1;
                tmpPriorities[tmpPumpCount] := pumpGroup[i].priority;
                tmpIndices[tmpPumpCount] := i;
            END_IF;
        END_FOR;

        // Initialize selection result
        FOR i := 1 TO 3 DO
            tmpSelectedIdx[i] := 0;
        END_FOR;
        tmpSelectedCount := 0;

        // Selection sort to find top 3 by priority (descending)
        FOR i := 1 TO tmpPumpCount DO
            tmpMaxIdx := i;
            tmpMaxVal := tmpPriorities[i];
            FOR j := i + 1 TO tmpPumpCount DO
                IF tmpPriorities[j] > tmpMaxVal THEN
                    tmpMaxIdx := j;
                    tmpMaxVal := tmpPriorities[j];
                END_IF;
            END_FOR;
            // Swap priorities
            tmpPriorities[tmpMaxIdx] := tmpPriorities[i];
            tmpPriorities[i] := tmpMaxVal;
            // Swap indices
            tmpSwap := tmpIndices[tmpMaxIdx];
            tmpIndices[tmpMaxIdx] := tmpIndices[i];
            tmpIndices[i] := tmpSwap;

            // Record top 3
            IF tmpSelectedCount < 3 THEN
                tmpSelectedCount := tmpSelectedCount + 1;
                tmpSelectedIdx[tmpSelectedCount] := tmpIndices[i];
            END_IF;
        END_FOR;

        // Apply run commands
        FOR i := 1 TO 5 DO
            tmpSel := FALSE;
            FOR j := 1 TO tmpSelectedCount DO
                IF tmpSelectedIdx[j] = i THEN
                    tmpSel := TRUE;
                    EXIT;
                END_IF;
            END_FOR;
            pumpGroup[i].RunComd := tmpSel;
        END_FOR;
    END_IF;
END_IF;
startPrev := start;

END_FUNCTION_BLOCK