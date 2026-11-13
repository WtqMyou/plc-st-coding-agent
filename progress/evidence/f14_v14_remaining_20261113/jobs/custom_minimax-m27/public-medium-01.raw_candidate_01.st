FUNCTION_BLOCK FB_PumpControl
VAR_INPUT
    mode  : BOOL;  // FALSE: Manual, TRUE: Automatic
    start : BOOL;
    stop  : BOOL;
END_VAR

VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR

VAR
    tmp_i          : INT;
    tmp_j          : INT;
    tmp_temp       : ST_Pump;
    tmp_tempIndex  : INT;
    tmp_sorted     : ARRAY[1..5] OF ST_Pump;
    tmp_order      : ARRAY[1..5] OF INT;
END_VAR

// ENGINEERING_CONTRACT
// ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
// │ Output/State              │ Activation                   │ Retention    │ Reset/Deactivation │ Same-scan │ Boundaries      │ PUB Clause     │
// │------------------------───│──────────────────────────────│──────────────│────────────────────│───────────│─────────────────│────────────────│
// │ pumpGroup[].RunComd FALSE │ stop=TRUE                    │ -            │ start=TRUE         │ -         │ 0–5 pumps       │ PUB001, PUB004 │
// │ pumpGroup[].RunComd TRUE  │ start=TRUE AND selected only │ Hold(start)  │ stop=TRUE          │ -         │ Manual: 1–5 pumps; Auto: 3 │ PUB001, PUB003 │
// │ pumpGroup[].RunComd TRUE  │ start=TRUE AND top-3 priority│ Hold(start)  │ stop=TRUE          │ -         │ Auto: exactly 3 │ PUB002         │
// └─────────────────────────────────────────────────────────────────────────────────────────────┘

// Stop has highest priority — de-energizes all pumps immediately
IF stop THEN
    FOR tmp_i := 1 TO 5 DO
        pumpGroup[tmp_i].RunComd := FALSE;
    END_FOR
    RETURN;
END_IF

IF NOT mode THEN
    // Manual mode: selected pump(s) follow start command
    FOR tmp_i := 1 TO 5 DO
        IF pumpGroup[tmp_i].selection THEN
            pumpGroup[tmp_i].RunComd := start;
        ELSE
            pumpGroup[tmp_i].RunComd := FALSE;
        END_IF
    END_FOR
ELSE
    // Automatic mode: top-3 priority pumps follow start command
    // Copy for sorting (preserves original pumpGroup indices)
    FOR tmp_i := 1 TO 5 DO
        tmp_sorted[tmp_i] := pumpGroup[tmp_i];
        tmp_order[tmp_i]  := tmp_i;
    END_FOR

    // Bubble sort by priority descending (stable: equal priority keeps original order)
    FOR tmp_i := 1 TO 4 DO
        FOR tmp_j := tmp_i + 1 TO 5 DO
            IF tmp_sorted[tmp_j].priority > tmp_sorted[tmp_i].priority THEN
                tmp_temp           := tmp_sorted[tmp_i];
                tmp_sorted[tmp_i]  := tmp_sorted[tmp_j];
                tmp_sorted[tmp_j]  := tmp_temp;

                tmp_tempIndex      := tmp_order[tmp_i];
                tmp_order[tmp_i]   := tmp_order[tmp_j];
                tmp_order[tmp_j]   := tmp_tempIndex;
            END_IF
        END_FOR
    END_FOR

    // Enable top-3 pumps (by original index) when start is asserted
    FOR tmp_i := 1 TO 5 DO
        IF tmp_i <= 3 THEN
            pumpGroup[tmp_order[tmp_i]].RunComd := start;
        ELSE
            pumpGroup[tmp_order[tmp_i]].RunComd := FALSE;
        END_IF
    END_FOR
END_IF

END_FUNCTION_BLOCK

(* CONTRACT_RULES [] *)