(* ENGINEERING_CONTRACT
  runningCount: combinational; activation every scan; clip demand to 0..5; no retention/reset; same-scan priority: computed first; range 0..5 [PUB001,S1].
  leadPump: stored selection; activation: positive demand with prevLead=0 -> global (hours,pump) min (tie smallest pump); positive prevLead valid + rotated TRUE and oldLeadHours-globalMinHours > 50 -> global min; else retain; deactivation/reset: demand<=0 -> 0; units 1..5,0=none [PUB004,S2,S3,S6,S7].
  lagPump: stored selection; activation/update: demand>=2 and (lead changed OR clipped demand rose) -> min among pumps excluding current lead (tie smallest pump); retention: otherwise while demand>=2; deactivation/reset: demand<=1 -> 0; units 1..5,0=none [PUB005,S8,S9].
  Arrays accessed with indices 1..5 only; previous outputs kept in static VAR [PUB006].
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB
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
    local_prevLeadPump : INT := 0;
    local_prevLagPump : INT := 0;
    local_prevRunningCount : INT := 0;
    local_demandClipped : INT;
    local_i : INT;
    local_minPumpAll : INT;
    local_minHoursAll : LINT;
    local_minPumpExcl : INT;
    local_minHoursExcl : LINT;
    local_firstFound : BOOL;
END_VAR

IF demand < 0 THEN
    local_demandClipped := 0;
ELSIF demand > 5 THEN
    local_demandClipped := 5;
ELSE
    local_demandClipped := demand;
END_IF;

runningCount := local_demandClipped;

IF local_demandClipped <= 0 THEN
    leadPump := 0;
    lagPump := 0;
ELSE
    local_minPumpAll := 1;
    local_minHoursAll := runHours[1];
    FOR local_i := 2 TO 5 DO
        IF (runHours[local_i] < local_minHoursAll) OR
           ((runHours[local_i] = local_minHoursAll) AND (local_i < local_minPumpAll)) THEN
            local_minPumpAll := local_i;
            local_minHoursAll := runHours[local_i];
        END_IF;
    END_FOR;

    IF local_prevLeadPump = 0 THEN
        leadPump := local_minPumpAll;
    ELSE
        leadPump := local_prevLeadPump;
        IF rotated THEN
            IF runHours[local_prevLeadPump] - local_minHoursAll > LINT#50 THEN
                leadPump := local_minPumpAll;
            END_IF;
        END_IF;
    END_IF;

    IF local_demandClipped = 1 THEN
        lagPump := 0;
    ELSE
        IF (leadPump <> local_prevLeadPump) OR (local_demandClipped > local_prevRunningCount) THEN
            local_minPumpExcl := 0;
            local_minHoursExcl := 0;
            local_firstFound := FALSE;
            FOR local_i := 1 TO 5 DO
                IF local_i <> leadPump THEN
                    IF NOT local_firstFound THEN
                        local_minPumpExcl := local_i;
                        local_minHoursExcl := runHours[local_i];
                        local_firstFound := TRUE;
                    ELSE
                        IF (runHours[local_i] < local_minHoursExcl) OR
                           ((runHours[local_i] = local_minHoursExcl) AND (local_i < local_minPumpExcl)) THEN
                            local_minPumpExcl := local_i;
                            local_minHoursExcl := runHours[local_i];
                        END_IF;
                    END_IF;
                END_IF;
            END_FOR;
            lagPump := local_minPumpExcl;
        ELSE
            lagPump := local_prevLagPump;
        END_IF;
    END_IF;
END_IF;

local_prevLeadPump := leadPump;
local_prevLagPump := lagPump;
local_prevRunningCount := runningCount;

END_FUNCTION_BLOCK