FUNCTION_BLOCK FB
VAR_OUTPUT
    leadPump : INT := 0;
    lagPump : INT := 0;
    runningCount : INT := 0;
END_VAR
VAR_INPUT
    demand : INT;
    runHours : ARRAY[1..5] OF LINT;
    rotated : BOOL;
END_VAR
VAR
    tmp_prevLead : INT := 0;
    tmp_prevRunning : INT := 0;
    tmp_selectLag : BOOL := FALSE;
    tmp_newLead : INT;
    minHours : LINT;
    i : INT;
END_VAR
VAR_TEMP
    newLag : INT;
END_VAR
(*
ENGINEERING_CONTRACT:
  [S1] runningCount = CLAMP(demand, 0, 5). PUB001/PUB011
  [S2] demand=0→leadPump=lagPump=0; demand=1→lagPump=0; demand≥2→leadPump≠lagPump, both 1..5. PUB002/PUB012
  [S3] Lead-change requires old lead hours > new lead hours + 50. PUB036
  [S4] Hysteresis: rotated=TRUE AND runHours[lead] > minHours + 50 → rotate to min-hours pump. PUB026/PUB027
  [S5] Lag pump selected ONLY on: initial, lead change, runningCount increase. PUB005/PUB031
  [S6] Initial lead selection: min (runHours, pump#). PUB028
  [S7] Lag pump: min (runHours, pump#) excluding lead pump. PUB029
  [S8] Demand=0 clears lead/lag immediately; next positive demand triggers fresh selection. PUB033/PUB034
  [S9] First FB invocation initializes all outputs to 0 (VAR_INIT). PUB041
  No edge detection on rotated; it is level-triggered. PUB026
  Array bounds: 1..5 only. PUB042
*)
(* CONTRACT_RULES [] *)

tmp_prevLead := leadPump;
tmp_prevRunning := runningCount;
tmp_selectLag := FALSE;

IF demand <= 0 THEN
    runningCount := 0;
    leadPump := 0;
    lagPump := 0;
ELSIF leadPump = 0 THEN
    runningCount := demand;
    tmp_newLead := 1;
    FOR i := 2 TO 5 DO
        IF runHours[i] < runHours[tmp_newLead] OR (runHours[i] = runHours[tmp_newLead] AND i < tmp_newLead) THEN
            tmp_newLead := i;
        END_IF;
    END_FOR;
    leadPump := tmp_newLead;
    tmp_selectLag := TRUE;
    IF demand >= 2 THEN
        newLag := 0;
        FOR i := 1 TO 5 DO
            IF i <> leadPump THEN
                IF newLag = 0 OR runHours[i] < runHours[newLag] OR (runHours[i] = runHours[newLag] AND i < newLag) THEN
                    newLag := i;
                END_IF;
            END_IF;
        END_FOR;
        lagPump := newLag;
    ELSE
        lagPump := 0;
    END_IF;
ELSE
    runningCount := demand;
    IF rotated AND runHours[leadPump] > minHours + 50 THEN
        tmp_newLead := 1;
        FOR i := 2 TO 5 DO
            IF runHours[i] < runHours[tmp_newLead] OR (runHours[i] = runHours[tmp_newLead] AND i < tmp_newLead) THEN
                tmp_newLead := i;
            END_IF;
        END_FOR;
        leadPump := tmp_newLead;
        tmp_selectLag := TRUE;
    END_IF;
    IF demand > tmp_prevRunning THEN
        tmp_newLead := 1;
        FOR i := 2 TO 5 DO
            IF runHours[i] < runHours[tmp_newLead] OR (runHours[i] = runHours[tmp_newLead] AND i < tmp_newLead) THEN
                tmp_newLead := i;
            END_IF;
        END_FOR;
        leadPump := tmp_newLead;
        tmp_selectLag := TRUE;
    END_IF;
    IF tmp_selectLag THEN
        IF demand >= 2 THEN
            newLag := 0;
            FOR i := 1 TO 5 DO
                IF i <> leadPump THEN
                    IF newLag = 0 OR runHours[i] < runHours[newLag] OR (runHours[i] = runHours[newLag] AND i < newLag) THEN
                        newLag := i;
                    END_IF;
                END_IF;
            END_FOR;
            lagPump := newLag;
        ELSE
            lagPump := 0;
        END_IF;
    END_IF;
END_IF;

minHours := runHours[1];
FOR i := 2 TO 5 DO
    IF runHours[i] < minHours THEN
        minHours := runHours[i];
    END_IF;
END_FOR;
END_FUNCTION_BLOCK