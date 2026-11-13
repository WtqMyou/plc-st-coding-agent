(*
ENGINEERING_CONTRACT
==================
State retention & activation:
- leadPump: latches until demand=0 clears it; reset_input=demand<=0 PUB004
- lagPump: latches until demand<2 clears it; hold on same-scan no-rise PUB005
- runningCount: combinational, equals clipped demand every scan PUB001
Initialization:
- First positive demand after demand=0 selects shortest-run pump as leadPump (PUB010)
- First positive demand sets lagPump if demand>=2 (PUB011)
Rotation behavior:
- rotated=TRUE + main.runHours - MIN(runHours) > 50 → switch to shortest (PUB012)
- rotated=FALSE → never switch, even if hysteresis gap exists (PUB012)
- rotated is level-triggered, evaluated every scan with current main hours (PUB012)
Backup selection moments:
- Initial selection | leadPump change | runningCount increase → recompute lagPump (PUB026)
- Otherwise retain previous lagPump (PUB028)
Direction conflict: N/A (no opposite movements in this pump-selection task)
Units: runHours in LINT hours, 50-hour hysteresis threshold (PUB012)
*)
(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR_INPUT
    demand     : INT;
    runHours   : ARRAY[1..5] OF LINT;
    rotated    : BOOL;
END_VAR
VAR_OUTPUT
    leadPump   : INT := 0;
    lagPump    : INT := 0;
    runningCount : INT := 0;
END_VAR
VAR
    prevLeadPump    : INT := 0;
    prevLagPump     : INT := 0;
    prevRunningCount : INT := 0;
    prevClippedDemand : INT := 0;
    wasDemandZero   : BOOL := TRUE;
END_VAR

VAR
    clippedDemand : INT;
    tmp_i         : INT;
    tmp_minHours  : LINT;
    tmp_minPump   : INT;
    tmp_secondMinHours : LINT;
    tmp_secondMinPump  : INT;
    tmp_mainHoursDiff  : LINT;
END_VAR

    // PUB001: Clip demand to 0..5
    IF demand < 0 THEN
        clippedDemand := 0;
    ELSIF demand > 5 THEN
        clippedDemand := 5;
    ELSE
        clippedDemand := demand;
    END_IF;

    runningCount := clippedDemand;

    // Clear all outputs when demand <= 0
    IF clippedDemand = 0 THEN
        leadPump := 0;
        lagPump  := 0;
        prevLeadPump    := 0;
        prevLagPump     := 0;
        prevRunningCount := 0;
        prevClippedDemand := 0;
        wasDemandZero   := TRUE;
    ELSE
        // Find pump with minimum run hours (for hysteresis check and selection)
        tmp_minHours := runHours[1];
        tmp_minPump  := 1;
        FOR tmp_i := 2 TO 5 DO
            IF runHours[tmp_i] < tmp_minHours THEN
                tmp_minHours := runHours[tmp_i];
                tmp_minPump  := tmp_i;
            ELSIF runHours[tmp_i] = tmp_minHours AND tmp_i < tmp_minPump THEN
                tmp_minPump  := tmp_i;
            END_IF;
        END_FOR;

        // Determine if this is initial selection (first positive demand after zero)
        IF wasDemandZero THEN
            // Initial selection: pick shortest-run pump as main
            leadPump   := tmp_minPump;
            lagPump    := 0;
            wasDemandZero := FALSE;
        ELSE
            // Not initial selection: check for rotation request
            IF rotated AND prevLeadPump <> 0 THEN
                // Compute main pump's hours difference from minimum
                tmp_mainHoursDiff := runHours[prevLeadPump] - tmp_minHours;
                IF tmp_mainHoursDiff > 50 THEN
                    // Hysteresis satisfied: switch to shortest-run pump
                    leadPump := tmp_minPump;
                ELSE
                    // Keep current main pump
                    leadPump := prevLeadPump;
                END_IF;
            ELSE
                // No rotation request or no previous main: keep current main
                leadPump := prevLeadPump;
            END_IF;
        END_IF;

        // Backup pump selection (PUB026, PUB028)
        IF clippedDemand >= 2 THEN
            // Need backup pump
            // Recompute lagPump only on: initial, leadPump change, runningCount increase
            IF wasDemandZero OR leadPump <> prevLeadPump OR clippedDemand > prevClippedDemand THEN
                // Find second-minimum pump (excluding leadPump)
                tmp_secondMinHours := 16#7FFFFFFFFFFFFFFF; // Large LINT value
                tmp_secondMinPump  := 0;
                FOR tmp_i := 1 TO 5 DO
                    IF tmp_i = leadPump THEN
                        // Skip main pump
                    ELSE
                        IF runHours[tmp_i] < tmp_secondMinHours THEN
                            tmp_secondMinHours := runHours[tmp_i];
                            tmp_secondMinPump  := tmp_i;
                        ELSIF runHours[tmp_i] = tmp_secondMinHours AND tmp_i < tmp_secondMinPump THEN
                            tmp_secondMinPump  := tmp_i;
                        END_IF;
                    END_IF;
                END_FOR;
                lagPump := tmp_secondMinPump;
            ELSE
                // Retain previous backup pump
                lagPump := prevLagPump;
            END_IF;
        ELSE
            // Demand < 2: no backup pump
            lagPump := 0;
        END_IF;
    END_IF;

    // Update previous state for next scan
    prevLeadPump     := leadPump;
    prevLagPump      := lagPump;
    prevRunningCount := runningCount;
    prevClippedDemand := clippedDemand;

END_FUNCTION_BLOCK