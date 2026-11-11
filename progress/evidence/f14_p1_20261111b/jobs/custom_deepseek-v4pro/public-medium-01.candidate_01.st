TYPE ST_Pump :
STRUCT
    priority : INT;   (* Read-only to the function block, larger value = higher priority *)
    selection : BOOL; (* Read-only, manual-selection state *)
    RunComd : BOOL;   (* Written by the function block, TRUE = run, FALSE = stop *)
END_STRUCT
END_TYPE


FUNCTION_BLOCK FB_MultiPumpControl
VAR_INPUT
    mode : BOOL;  (* FALSE = Manual, TRUE = Automatic *)
    start : BOOL; (* Start button *)
    stop : BOOL;  (* Stop button - stops all pumps *)
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    runActive : BOOL;       (* Internal run enable latch *)
    startPrev : BOOL;       (* Previous cycle start for edge detection *)
    stopPrev : BOOL;        (* Previous cycle stop for edge detection *)
    startRising : BOOL;     (* Rising edge of start *)
    stopRising : BOOL;      (* Rising edge of stop *)
    idx : ARRAY[1..5] OF INT; (* Indices for sorting *)
    i : INT;
    j : INT;
    temp : INT;
END_VAR

    (* Edge detection *)
    startRising := start AND NOT startPrev;
    stopRising := stop AND NOT stopPrev;
    startPrev := start;
    stopPrev := stop;

    (* Stop has priority over start if both edges occur in the same scan *)
    IF stopRising THEN
        runActive := FALSE;
    ELSIF startRising THEN
        runActive := TRUE;
    END_IF;

    IF NOT runActive THEN
        (* All pumps stopped when runActive is FALSE *)
        FOR i := 1 TO 5 DO
            pumpGroup[i].RunComd := FALSE;
        END_FOR;
    ELSE
        IF NOT mode THEN
            (* -------- Manual mode --------
               Run each pump exactly according to its manual selection. *)
            FOR i := 1 TO 5 DO
                pumpGroup[i].RunComd := pumpGroup[i].selection;
            END_FOR;
        ELSE
            (* -------- Automatic mode --------
               Select the 3 pumps with the highest priority.
               Tie-break: lower pump index has higher priority. *)

            (* Initialize index array *)
            FOR i := 1 TO 5 DO
                idx[i] := i;
            END_FOR;

            (* Sort indices by priority descending, then by index ascending *)
            FOR i := 1 TO 4 DO
                FOR j := i + 1 TO 5 DO
                    IF (pumpGroup[idx[j]].priority > pumpGroup[idx[i]].priority) OR
                       ((pumpGroup[idx[j]].priority = pumpGroup[idx[i]].priority) AND
                        (idx[j] < idx[i])) THEN
                        temp := idx[i];
                        idx[i] := idx[j];
                        idx[j] := temp;
                    END_IF;
                END_FOR;
            END_FOR;

            (* Clear all run commands first *)
            FOR i := 1 TO 5 DO
                pumpGroup[i].RunComd := FALSE;
            END_FOR;

            (* Set RunComd TRUE for the three highest priority pumps *)
            FOR i := 1 TO 3 DO
                pumpGroup[idx[i]].RunComd := TRUE;
            END_FOR;
        END_IF;
    END_IF;

END_FUNCTION_BLOCK