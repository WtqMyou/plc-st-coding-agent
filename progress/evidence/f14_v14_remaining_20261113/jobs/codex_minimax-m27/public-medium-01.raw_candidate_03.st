TYPE ST_Pump :
STRUCT
    priority : INT;
    selection : BOOL;
    RunComd : BOOL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_MultiPumpControl
VAR_INPUT
    mode : BOOL;          // FALSE: Manual mode, TRUE: Automatic mode
    start : BOOL;         // Start button
    stop : BOOL;          // Stop button
END_VAR

VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR

VAR
    startRisingEdge : BOOL;               // Rising edge of start
    tmp_startPrev : BOOL;                 // Previous start state
    tmp_i : INT;                          // Loop counter
    tmp_j : INT;                          // Loop counter
    tmp_swap : INT;                       // Swap variable
    tmp_pumpIdx : ARRAY[1..5] OF INT;    // Pump indices for sorting
    tmp_priorities : ARRAY[1..5] OF INT; // Priority copy for sorting
    tmp_swap_idx : INT;                   // Index swap
END_VAR

// ENGINEERING_CONTRACT:
// PUB001 [L91-265]: mode=FALSE → manual; start activates pumps where selection=TRUE
// PUB001 [L91-265]: mode=TRUE → automatic; start activates top-3 by priority (3-in-2-standby)
// PUB002 [L266-350]: stop halts all pumps; no retention on stop (level-triggered)
// PUB003 [L351-463]: Rising edge on start evaluates selection; stop has same-scan priority
// PUB004 [L464-652]: Only RunComd is written; priority/selection are read-only

(* CONTRACT_RULES [] *)

startRisingEdge := start AND NOT tmp_startPrev;

IF stop THEN
    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := FALSE;
    END_FOR;
ELSIF startRisingEdge THEN
    IF mode = FALSE THEN
        FOR tmp_i := 1 TO 5 DO
            IF pumpGroup[tmp_i].selection THEN
                pumpGroup[tmp_i].RunComd := TRUE;
            END_IF;
        END_FOR;
    ELSE
        FOR tmp_i := 1 TO 5 DO
            tmp_priorities[tmp_i] := pumpGroup[tmp_i].priority;
            tmp_pumpIdx[tmp_i] := tmp_i;
        END_FOR;
        FOR tmp_i := 1 TO 4 DO
            FOR tmp_j := tmp_i + 1 TO 5 DO
                IF tmp_priorities[tmp_j] > tmp_priorities[tmp_i] THEN
                    tmp_swap := tmp_priorities[tmp_i];
                    tmp_priorities[tmp_i] := tmp_priorities[tmp_j];
                    tmp_priorities[tmp_j] := tmp_swap;
                    tmp_swap_idx := tmp_pumpIdx[tmp_i];
                    tmp_pumpIdx[tmp_i] := tmp_pumpIdx[tmp_j];
                    tmp_pumpIdx[tmp_j] := tmp_swap_idx;
                END_IF;
            END_FOR;
        END_FOR;
        FOR tmp_i := 1 TO 5 DO
            IF tmp_i <= 3 THEN
                pumpGroup[tmp_pumpIdx[tmp_i]].RunComd := TRUE;
            ELSE
                pumpGroup[tmp_pumpIdx[tmp_i]].RunComd := FALSE;
            END_IF;
        END_FOR;
    END_IF;
END_IF;

tmp_startPrev := start;
END_FUNCTION_BLOCK