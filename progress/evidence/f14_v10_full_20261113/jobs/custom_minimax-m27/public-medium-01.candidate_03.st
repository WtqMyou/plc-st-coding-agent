(* ENGINEERING_CONTRACT
 * PUB001: Mode selection - mode=FALSE selects Manual, mode=TRUE selects Automatic.
 * PUB002: Manual mode - read pumpGroup[].selection; write RunComd=TRUE on start for selected pumps.
 * PUB003: Automatic mode - sort 5 pumps by priority DESC, select top 3; write RunComd=TRUE for those pumps.
 * PUB004: Stop button - write RunComd=FALSE to all pumps regardless of mode (explicit reset).
 * Activation: R_TRIG on start/stop for single-scan edge detection (not level-triggered).
 * Retention: RunComd persists across scans until explicitly changed; no implicit state clear.
 * Priority rules: No specified simultaneous-operation conflict resolution; last command wins per scan.
 * Units: Priority is INT; no explicit range; 0 treated as lowest/skip. Lower array index wins ties.
 * Boundaries: Automatic mode selects exactly 3 pumps (or fewer if priority<=0); min 0 pumps selected.
 * CONTRACT_RULES [{"kind":"hold_until_reset","output":"pumpGroup","set_input":"start","reset_input":"stop"}]
 *)
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
    startTrig     : R_TRIG;
    stopTrig      : R_TRIG;
    tmp_pumpCount : INT;
    tmp_priorities : ARRAY[1..5] OF INT;
    tmp_indices   : ARRAY[1..5] OF INT;
    tmp_result    : ARRAY[1..3] OF INT;
    tmp_resultCount : INT;
    i             : INT;
    j             : INT;
    maxIdx        : INT;
    maxVal        : INT;
    tmpSwap       : INT;
    isSelected    : BOOL;
    k             : INT;
END_VAR

// Rising-edge detection for start and stop buttons
startTrig(CLK := start);
stopTrig(CLK := stop);

// Stop button has highest priority - stops all pumps in any mode
IF stopTrig.Q THEN
    pumpGroup[1].RunComd := FALSE;
    pumpGroup[2].RunComd := FALSE;
    pumpGroup[3].RunComd := FALSE;
    pumpGroup[4].RunComd := FALSE;
    pumpGroup[5].RunComd := FALSE;
    RETURN;
END_IF;

// Start command processed when stop is not active
IF startTrig.Q THEN
    IF mode = FALSE THEN
        // Manual mode: start selected pumps based on selection flag
        pumpGroup[1].RunComd := pumpGroup[1].selection;
        pumpGroup[2].RunComd := pumpGroup[2].selection;
        pumpGroup[3].RunComd := pumpGroup[3].selection;
        pumpGroup[4].RunComd := pumpGroup[4].selection;
        pumpGroup[5].RunComd := pumpGroup[5].selection;
    ELSE
        // Automatic mode: select top 3 pumps by priority (highest priority first)
        // Collect pumps with positive priority
        tmp_pumpCount := 0;
        FOR i := 1 TO 5 DO
            IF pumpGroup[i].priority > 0 THEN
                tmp_pumpCount := tmp_pumpCount + 1;
                tmp_priorities[tmp_pumpCount] := pumpGroup[i].priority;
                tmp_indices[tmp_pumpCount] := i;
            END_IF;
        END_FOR;

        // Initialize result array
        tmp_result[1] := 0;
        tmp_result[2] := 0;
        tmp_result[3] := 0;
        tmp_resultCount := 0;

        // Selection sort to find top 3 pumps by priority (descending)
        FOR i := 1 TO tmp_pumpCount DO
            maxIdx := i;
            maxVal := tmp_priorities[i];
            FOR j := i + 1 TO tmp_pumpCount DO
                IF tmp_priorities[j] > maxVal THEN
                    maxIdx := j;
                    maxVal := tmp_priorities[j];
                END_IF;
            END_FOR;
            // Swap to move max to position i
            tmp_priorities[maxIdx] := tmp_priorities[i];
            tmp_priorities[i] := maxVal;
            tmpSwap := tmp_indices[maxIdx];
            tmp_indices[maxIdx] := tmp_indices[i];
            tmp_indices[i] := tmpSwap;

            // Record result (up to 3)
            IF tmp_resultCount < 3 THEN
                tmp_resultCount := tmp_resultCount + 1;
                tmp_result[tmp_resultCount] := tmp_indices[i];
            END_IF;
        END_FOR;

        // Apply run commands based on sorted selection
        FOR i := 1 TO 5 DO
            isSelected := FALSE;
            FOR k := 1 TO tmp_resultCount DO
                IF tmp_result[k] = i THEN
                    isSelected := TRUE;
                    EXIT;
                END_IF;
            END_FOR;
            pumpGroup[i].RunComd := isSelected;
        END_FOR;
    END_IF;
END_IF;

END_FUNCTION_BLOCK