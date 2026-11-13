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
    local_clamped : INT := 0;
    local_minPump : INT := 0;
    local_candidateLag : INT := 0;
    local_prevLead : INT := 0;
    local_prevLag : INT := 0;
    local_prevRunningCount : INT := 0;
    local_leadChanged : BOOL := FALSE;
    local_countRise : BOOL := FALSE;
    tmp_i : INT := 0;
END_VAR

(* ENGINEERING_CONTRACT
   runningCount: clamps demand to 0..5 each scan; demand<=0 also clears selections (PUB001/S1/S5).
   leadPump activation: positive restart/init selects global min by (hours,pump#).
   leadPump hold: level rotated swaps only when previous valid lead-min>50h; otherwise holds; no rotated holds (PUB002/S3/S6/S7).
   lead/lag reset: demand=0 sets both 0 same scan (S4).
   lagPump activation/reselect: only initial, clamped demand rise, or lead change; choose min excluding new lead (PUB003/S8).
   lagPump hold: while demand>=2, lead unchanged and count not rising, lag remains previous (S9).
   Same-scan order: clamp->lead->lag; all hours LINT, threshold strict >50; array slots 1..5 only.
*)

(* CONTRACT_RULES [] *)

IF demand < 0 THEN
    local_clamped := 0;
ELSIF demand > 5 THEN
    local_clamped := 5;
ELSE
    local_clamped := demand;
END_IF;

runningCount := local_clamped;

IF local_clamped = 0 THEN
    leadPump := 0;
    lagPump := 0;
ELSE
    local_minPump := 1;
    FOR tmp_i := 2 TO 5 DO
        IF runHours[tmp_i] < runHours[local_minPump] THEN
            local_minPump := tmp_i;
        END_IF;
    END_FOR;

    IF (local_prevLead < 1) OR (local_prevLead > 5) THEN
        leadPump := local_minPump;
    ELSIF NOT rotated THEN
        leadPump := local_prevLead;
    ELSIF (runHours[local_prevLead] - runHours[local_minPump]) > 50 THEN
        leadPump := local_minPump;
    ELSE
        leadPump := local_prevLead;
    END_IF;

    IF local_clamped < 2 THEN
        lagPump := 0;
    ELSE
        local_leadChanged := (leadPump <> local_prevLead);
        local_countRise := local_clamped > local_prevRunningCount;

        IF local_leadChanged OR local_countRise THEN
            local_candidateLag := 0;
            FOR tmp_i := 1 TO 5 DO
                IF tmp_i <> leadPump THEN
                    IF local_candidateLag = 0 THEN
                        local_candidateLag := tmp_i;
                    ELSIF runHours[tmp_i] < runHours[local_candidateLag] THEN
                        local_candidateLag := tmp_i;
                    END_IF;
                END_IF;
            END_FOR;
            lagPump := local_candidateLag;
        ELSE
            lagPump := local_prevLag;
        END_IF;
    END_IF;
END_IF;

local_prevLead := leadPump;
local_prevLag := lagPump;
local_prevRunningCount := local_clamped;

END_FUNCTION_BLOCK