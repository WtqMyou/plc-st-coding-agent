(* ENGINEERING_CONTRACT
 * PUB001: Mode selection - mode=FALSE selects Manual, mode=TRUE selects Automatic.
 * PUB002: Manual mode - read pumpGroup[].selection; write RunComd=TRUE on start for selected pumps.
 * PUB003: Automatic mode - sort 5 pumps by priority DESC, select top 3; write RunComd=TRUE for those pumps.
 * PUB004: Stop button - write RunComd=FALSE to all pumps regardless of mode (explicit reset).
 * Activation: R_TRIG on start/stop for single-scan edge detection (not level-triggered).
 * Retention: RunComd persists across scans until explicitly changed; no implicit state clear.
 * Priority rules: No specified simultaneous-operation conflict resolution; last command wins per scan.
 * Units: Priority is INT; no explicit range; 0 or negative treated as skip. Lower array index wins ties.
 * Boundaries: Automatic mode selects up to 3 pumps with positive priority.
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
    startTrig    : R_TRIG;
    stopTrig     : R_TRIG;
    tmp_pumpCount   : INT;
    tmp_priorities  : ARRAY[1..5] OF INT;
    tmp_indices     : ARRAY[1..5] OF INT;
    tmp_result      : ARRAY[1..3] OF INT;
    tmp_resultCount : INT;
    tmp_i, tmp_j, tmp_swap : INT;
    tmp_isSelected  : BOOL;
    tmp_maxIdx, tmp_maxVal : INT;
END_VAR

// Rising-edge detection for start and stop buttons
startTrig(CLK := start);
stopTrig(CLK := stop);

// Stop button has highest priority - stops all pumps in any mode
IF stopTrig.Q THEN
    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := FALSE;
    END_FOR;
    RETURN;
END_IF;

// Start command processed when stop is not active
IF startTrig.Q THEN
    IF mode = FALSE THEN
        // Manual mode: start selected pumps based on selection flag
        FOR tmp_i := 1 TO 5 DO
            pumpGroup[tmp_i].RunComd := pumpGroup[tmp_i].selection;
        END_FOR;
    ELSE
        // Automatic mode: select top 3 pumps by priority (highest priority first)
        tmp_pumpCount := 0;
        
        // Collect pumps with positive priority
        FOR tmp_i := 1 TO 5 DO
            IF pumpGroup[tmp_i].priority > 0 THEN
                tmp_pumpCount := tmp_pumpCount + 1;
                tmp_priorities[tmp_pumpCount] := pumpGroup[tmp_i].priority;
                tmp_indices[tmp_pumpCount] := tmp_i;
            END_IF;
        END_FOR;
        
        // Initialize result array
        FOR tmp_i := 1 TO 3 DO
            tmp_result[tmp_i] := 0;
        END_FOR;
        tmp_resultCount := 0;
        
        // Selection sort to find top 3 pumps by priority (descending)
        FOR tmp_i := 1 TO tmp_pumpCount DO
            tmp_maxIdx := tmp_i;
            tmp_maxVal := tmp_priorities[tmp_i];
            FOR tmp_j := tmp_i + 1 TO tmp_pumpCount DO
                IF tmp_priorities[tmp_j] > tmp_maxVal THEN
                    tmp_maxIdx := tmp_j;
                    tmp_maxVal := tmp_priorities[tmp_j];
                END_IF;
            END_FOR;
            
            // Swap to move max to position tmp_i
            tmp_priorities[tmp_maxIdx] := tmp_priorities[tmp_i];
            tmp_priorities[tmp_i] := tmp_maxVal;
            tmp_swap := tmp_indices[tmp_maxIdx];
            tmp_indices[tmp_maxIdx] := tmp_indices[tmp_i];
            tmp_indices[tmp_i] := tmp_swap;
            
            // Record result (up to 3)
            IF tmp_resultCount < 3 THEN
                tmp_resultCount := tmp_resultCount + 1;
                tmp_result[tmp_resultCount] := tmp_indices[tmp_i];
            END_IF;
        END_FOR;
        
        // Apply run commands based on sorted selection
        FOR tmp_i := 1 TO 5 DO
            tmp_isSelected := FALSE;
            FOR tmp_j := 1 TO tmp_resultCount DO
                IF tmp_result[tmp_j] = tmp_i THEN
                    tmp_isSelected := TRUE;
                    EXIT;
                END_IF;
            END_FOR;
            pumpGroup[tmp_i].RunComd := tmp_isSelected;
        END_FOR;
    END_IF;
END_IF;

END_FUNCTION_BLOCK