(*--------------------------------------------------------------
  Data‑type for a single pump
--------------------------------------------------------------*)
TYPE ST_Pump : STRUCT
    priority  : INT;     // Read‑only priority (larger → higher priority)
    selection : BOOL;    // Read‑only manual‑selection flag
    RunComd   : BOOL;    // Write‑only run command (TRUE = start, FALSE = stop)
END_STRUCT
END_TYPE

(*--------------------------------------------------------------
  Multi‑pump switching control function block

  Inputs:
    mode   – FALSE = manual mode, TRUE = automatic mode
    start  – start push‑button (rising‑edge triggered)
    stop   – stop push‑button (rising‑edge triggered)

  In‑Out:
    pumpGroup – array of 5 pump records (priority & selection are read,
                RunComd is written)
--------------------------------------------------------------*)
FUNCTION_BLOCK MultiPumpControl
VAR_INPUT
    mode  : BOOL;   // FALSE = Manual, TRUE = Automatic
    start : BOOL;   // Start push‑button (rising edge)
    stop  : BOOL;   // Stop push‑button (rising edge)
END_VAR
VAR_IN_OUT
    pumpGroup : ARRAY[1..5] OF ST_Pump;
END_VAR
VAR
    startPrev : BOOL := FALSE;   // Edge‑detection memory for START
    stopPrev  : BOOL := FALSE;   // Edge‑detection memory for STOP
    i, j, tmp : INT;             // Loop counters & temp for sorting
    sortedIdx : ARRAY[1..5] OF INT; // Indices of pumps sorted by priority
END_VAR

(* -------------------------------------------------------------
   STOP – rising edge of the STOP button stops all pumps
   ------------------------------------------------------------- *)
IF stop AND NOT stopPrev THEN
    FOR i := 1 TO 5 DO
        pumpGroup[i].RunComd := FALSE;
    END_FOR;
END_IF;
stopPrev := stop;

(* -------------------------------------------------------------
   START – rising edge of the START button starts the selected
   pump(s) in manual mode, or the three highest‑priority pumps
   in automatic mode.
   ------------------------------------------------------------- *)
IF start AND NOT startPrev THEN
    IF NOT mode THEN
        (* ---- Manual mode ---- *)
        (* Start every pump whose selection flag is TRUE *)
        FOR i := 1 TO 5 DO
            IF pumpGroup[i].selection THEN
                pumpGroup[i].RunComd := TRUE;
            END_IF;
        END_FOR;
    ELSE
        (* ---- Automatic mode ---- *)
        (* 1) Build a list of pump indices sorted by priority (descending) *)
        FOR i := 1 TO 5 DO
            sortedIdx[i] := i;
        END_FOR;

        (* Simple bubble‑sort (stable) – fine for only 5 pumps *)
        FOR i := 1 TO 4 DO
            FOR j := i+1 TO 5 DO
                IF pumpGroup[sortedIdx[j]].priority > pumpGroup[sortedIdx[i]].priority THEN
                    tmp := sortedIdx[i];
                    sortedIdx[i] := sortedIdx[j];
                    sortedIdx[j] := tmp;
                END_IF;
            END_FOR;
        END_FOR;

        (* 2) Drive the three highest‑priority pumps, keep the rest on standby *)
        FOR i := 1 TO 5 DO
            IF i <= 3 THEN
                pumpGroup[sortedIdx[i]].RunComd := TRUE;   // start
            ELSE
                pumpGroup[sortedIdx[i]].RunComd := FALSE;  // standby
            END_IF;
        END_FOR;
    END_IF;
END_IF;
startPrev := start;

END_FUNCTION_BLOCK