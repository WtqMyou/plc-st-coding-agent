FUNCTION_BLOCK FB
VAR_INPUT
    demand     : INT;
    runHours   : ARRAY[1..5] OF LINT;
    rotated    : BOOL;
END_VAR
VAR_OUTPUT
    leadPump    : INT := 0;
    lagPump     : INT := 0;
    runningCount: INT := 0;
END_VAR
VAR
    prevDemand   : INT := 0;
    prevLeadPump : INT := 0;
    tmp_minHours : LINT;
    tmp_minPump  : INT;
    tmp_lagPump  : INT;
    tmp_lagHours : LINT;
    tmp_lagChanged: BOOL;
    i            : INT;
    clippedDemand: INT;
    demandIncrease: BOOL;
END_VAR
VAR_TEMP
    tmp_leadHours: LINT;
    tmp_leadPump : INT;
END_VAR
// ---------------------------------------------------------------------
// ENGINEERING_CONTRACT
// PubRefs: PUB001–PUB046
// State retention: leadPump/lagPump held across scans until demand=0 (PUB003/PUB004/PUB026)
//   or until hysteresis rotation condition satisfied (PUB009/PUB030)
// Output retention: runningCount strictly tracks clipped demand every scan (PUB001/PUB003)
//   lagPump retained when no trigger event occurs (PUB008/PUB042)
// Reset on demand=0: leadPump=lagPump=0 immediately this scan (PUB003/PUB027)
// Initial state (first scan): leadPump=0, lagPump=0, runningCount=0 (PUB029)
// Hysteresis: rotation only when runHours[prevLead] - min(runHours[*]) > 50 strictly (PUB030/PUB040)
// Lag trigger: initial selection OR lead change OR runningCount increase (PUB008/PUB043)
// Lag exclusion: leadPump never equals lagPump when demand>=2 (PUB003/PUB004)
// ---------------------------------------------------------------------
// CONTRACT_RULES
// (No unconditional Boolean output latches specified in this task)
// []

// Clip demand to 0..5
IF demand < 0 THEN
    clippedDemand := 0;
ELSIF demand > 5 THEN
    clippedDemand := 5;
ELSE
    clippedDemand := demand;
END_IF

runningCount := clippedDemand;
demandIncrease := (clippedDemand > prevDemand);

// Compute global minimum (runHours, pump#) for hysteresis check
tmp_minHours := runHours[1];
tmp_minPump := 1;
FOR i := 2 TO 5 DO
    IF runHours[i] < tmp_minHours OR (runHours[i] = tmp_minHours AND i < tmp_minPump) THEN
        tmp_minHours := runHours[i];
        tmp_minPump := i;
    END_IF
END_FOR

// Demand zero: clear both outputs immediately
IF clippedDemand = 0 THEN
    leadPump := 0;
    lagPump := 0;
ELSE
    // Positive demand branch
    IF prevLeadPump = 0 THEN
        // PUB003/PUB026: Initial selection - pick (runHours, pump#) minimum as lead
        tmp_leadHours := runHours[1];
        tmp_leadPump := 1;
        FOR i := 2 TO 5 DO
            IF runHours[i] < tmp_leadHours OR (runHours[i] = tmp_leadHours AND i < tmp_leadPump) THEN
                tmp_leadHours := runHours[i];
                tmp_leadPump := i;
            END_IF
        END_FOR
        leadPump := tmp_leadPump;
        tmp_lagChanged := TRUE;
    ELSE
        // PUB009/PUB030: Subsequent scan - apply hysteresis rotation
        // Only switch if rotated=TRUE AND (prevLead runHours - min runHours) > 50 strictly
        IF rotated AND (runHours[prevLeadPump] - tmp_minHours > 50) THEN
            leadPump := tmp_minPump;
            tmp_lagChanged := TRUE;
        ELSE
            // PUB006/PUB042: No rotation request or hysteresis not met - retain lead
            leadPump := prevLeadPump;
            tmp_lagChanged := FALSE;
        END_IF
    END_IF

    // PUB008/PUB043: Lag pump selection (triggered by initial/lead-change/runningCount-increase)
    IF clippedDemand >= 2 THEN
        IF tmp_lagChanged OR demandIncrease THEN
            tmp_lagPump := 0;
            tmp_lagHours := LINT#16#7FFFFFFFFFFFFFFF;
            FOR i := 1 TO 5 DO
                IF i <> leadPump THEN
                    IF runHours[i] < tmp_lagHours OR (runHours[i] = tmp_lagHours AND i < tmp_lagPump) THEN
                        tmp_lagHours := runHours[i];
                        tmp_lagPump := i;
                    END_IF
                END_IF
            END_FOR
            lagPump := tmp_lagPump;
        END_IF
        // ELSE: retain prev lagPump (no assignment)
    ELSE
        // PUB003: demand = 1, lagPump must be 0
        lagPump := 0;
    END_IF
END_IF

// Update previous-state trackers for next scan
prevDemand := clippedDemand;
prevLeadPump := leadPump;
END_FUNCTION_BLOCK