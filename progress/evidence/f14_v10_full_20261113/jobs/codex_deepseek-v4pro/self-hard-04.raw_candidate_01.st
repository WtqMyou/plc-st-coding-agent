FUNCTION_BLOCK FB
(* ENGINEERING_CONTRACT
runningCount: activation=each scan; value=clamp(demand,0,5); reset=none; priority=clamp before pump selection.
leadPump: activation=demand>0 sets initial min or holds; hold=no rotated/insufficient margin; reset=demand<=0 -> 0; change iff rotated AND old-main - min > 50; new lead is used for lag in same scan.
lagPump: activation=demand>=2 on initial, lead-change, or count-rise chooses min non-lead pump; hold=all other demand>=2 scans; reset=demand<=1 -> 0.
units/bounds: demand/pump count 0..5, pump 1..5, runHours LINT hours, hysteresis margin strict >50 h.
*)
(* CONTRACT_RULES [] *)
VAR_INPUT
    demand : INT;
    runHours : ARRAY[1..5] OF LINT;
    rotated : BOOL;
END_VAR
VAR_OUTPUT
    leadPump : INT;
    lagPump : INT;
    runningCount : INT;
END_VAR
VAR
    local_prevLead : INT := 0;
    local_prevCount : INT := 0;
    local_clampedDemand : INT;
    local_minPump : INT;
    local_lagPump : INT;
    local_leadChanged : BOOL;
    local_countRising : BOOL;
    local_index : INT;
END_VAR

    IF demand < 0 THEN
        local_clampedDemand := 0;
    ELSIF demand > 5 THEN
        local_clampedDemand := 5;
    ELSE
        local_clampedDemand := demand;
    END_IF;

    runningCount := local_clampedDemand;
    local_countRising := local_clampedDemand > local_prevCount;

    IF local_clampedDemand = 0 THEN
        leadPump := 0;
        lagPump := 0;
    ELSE
        local_minPump := 1;
        FOR local_index := 2 TO 5 DO
            IF runHours[local_index] < runHours[local_minPump] THEN
                local_minPump := local_index;
            ELSIF runHours[local_index] = runHours[local_minPump] THEN
                IF local_index < local_minPump THEN
                    local_minPump := local_index;
                END_IF;
            END_IF;
        END_FOR;

        IF local_prevLead = 0 THEN
            leadPump := local_minPump;
        ELSE
            leadPump := local_prevLead;
            IF rotated AND (runHours[local_prevLead] - runHours[local_minPump] > 50) THEN
                leadPump := local_minPump;
            END_IF;
        END_IF;

        local_leadChanged := leadPump <> local_prevLead;

        IF local_clampedDemand = 1 THEN
            lagPump := 0;
        ELSE
            IF local_leadChanged OR local_countRising THEN
                local_lagPump := 0;
                FOR local_index := 1 TO 5 DO
                    IF local_index <> leadPump THEN
                        IF local_lagPump = 0 THEN
                            local_lagPump := local_index;
                        ELSIF runHours[local_index] < runHours[local_lagPump] THEN
                            local_lagPump := local_index;
                        ELSIF runHours[local_index] = runHours[local_lagPump] THEN
                            IF local_index < local_lagPump THEN
                                local_lagPump := local_index;
                            END_IF;
                        END_IF;
                    END_IF;
                END_FOR;
                lagPump := local_lagPump;
            END_IF;
        END_IF;
    END_IF;

    local_prevLead := leadPump;
    local_prevCount := runningCount;

END_FUNCTION_BLOCK