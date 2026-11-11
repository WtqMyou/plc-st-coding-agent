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
    prevDemand       : INT := 0;
    prevLeadPump     : INT := 0;
    prevLagPump      : INT := 0;
    prevRunningCount : INT := 0;
END_VAR

VAR_TEMP
    clippedDemand : INT;
    minHours      : LINT;
    minPump       : INT;
    minLagHours   : LINT;
    minLagPump    : INT;
    i             : INT;
    hourDiff      : LINT;
END_VAR

// Clip demand to 0..5
clippedDemand := LIMIT(0, demand, 5);
runningCount := clippedDemand;

// Find minimum run hours pump
minHours := runHours[1];
minPump := 1;
FOR i := 2 TO 5 DO
    IF runHours[i] < minHours OR (runHours[i] = minHours AND i < minPump) THEN
        minHours := runHours[i];
        minPump := i;
    END_IF
END_FOR

// Demand = 0: clear pumps
IF clippedDemand = 0 THEN
    leadPump := 0;
    lagPump := 0;
ELSE
    // Demand > 0: select/keep lead pump
    IF prevLeadPump = 0 THEN
        // Initial selection or restart: select minimum (runHours, pumpNumber)
        leadPump := minPump;
    ELSIF rotated AND (runHours[prevLeadPump] - minHours > LINT#50) THEN
        // Hysteresis: only switch if rotated AND gap > 50 hours
        leadPump := minPump;
    ELSE
        // Keep previous lead pump
        leadPump := prevLeadPump;
    END_IF
    
    // Lag pump selection
    IF clippedDemand >= 2 THEN
        // Need lag pump
        IF lagPump = 0 OR leadPump <> prevLeadPump OR clippedDemand > prevRunningCount THEN
            // Initial selection, main pump changed, or running count increased
            minLagHours := LINT#999999999;
            minLagPump := 0;
            FOR i := 1 TO 5 DO
                IF i <> leadPump THEN
                    IF runHours[i] < minLagHours OR (runHours[i] = minLagHours AND i < minLagPump) THEN
                        minLagHours := runHours[i];
                        minLagPump := i;
                    END_IF
                END_IF
            END_FOR
            lagPump := minLagPump;
        ELSE
            // Keep previous lag pump
            lagPump := prevLagPump;
        END_IF
    ELSE
        lagPump := 0;
    END_IF
END_IF

// Update previous values
prevDemand := clippedDemand;
prevLeadPump := leadPump;
prevLagPump := lagPump;
prevRunningCount := runningCount;

END_FUNCTION_BLOCK