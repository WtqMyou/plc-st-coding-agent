FUNCTION_BLOCK FB
VAR
    prevDemand: INT := 0;
    prevLeadPump: INT := 0;
    prevRunningCount: INT := 0;
    prevLagPump: INT := 0;
    leadPump: INT := 0;
    lagPump: INT := 0;
    runningCount: INT := 0;
    minHours: LINT;
    minPumpIdx: INT;
    secondMinHours: LINT;
    secondMinIdx: INT;
    hoursDiff: LINT;
    needInitialLead: BOOL;
    needSwitchLead: BOOL;
    needRefreshLag: BOOL;
    i: INT;
    h: LINT;
END_VAR

// Clip demand to 0..5
IF demand < 0 THEN
    runningCount := 0;
ELSIF demand > 5 THEN
    runningCount := 5;
ELSE
    runningCount := demand;
END_IF;

// Detect state transitions
needInitialLead := (prevDemand = 0) AND (runningCount > 0);
needRefreshLag := (runningCount > prevRunningCount) OR (leadPump <> prevLeadPump);

// Find pump with minimum (runHours, pumpIdx)
minHours := runHours[1];
minPumpIdx := 1;
FOR i := 2 TO 5 DO
    h := runHours[i];
    IF (h < minHours) OR ((h = minHours) AND (i < minPumpIdx)) THEN
        minHours := h;
        minPumpIdx := i;
    END_IF;
END_FOR;

// Lead pump hysteresis check
IF leadPump >= 1 AND leadPump <= 5 THEN
    hoursDiff := runHours[leadPump] - minHours;
ELSE
    hoursDiff := 0;
END_IF;
needSwitchLead := (prevLeadPump <> 0) AND rotated AND (hoursDiff > 50);

// Demand = 0: clear both pumps immediately
IF runningCount = 0 THEN
    leadPump := 0;
    lagPump := 0;
    needRefreshLag := FALSE;
    needSwitchLead := FALSE;
END_IF;

// Handle lead pump change
IF needSwitchLead THEN
    leadPump := minPumpIdx;
    needRefreshLag := TRUE;
ELSIF needInitialLead THEN
    leadPump := minPumpIdx;
END_IF;

// Lag pump selection
IF needRefreshLag AND runningCount > 0 THEN
    secondMinHours := 16#7FFFFFFFFFFFFFFF;
    secondMinIdx := 0;
    FOR i := 1 TO 5 DO
        IF i <> leadPump THEN
            h := runHours[i];
            IF (h < secondMinHours) OR ((h = secondMinHours) AND (i < secondMinIdx)) THEN
                secondMinHours := h;
                secondMinIdx := i;
            END_IF;
        END_IF;
    END_FOR;
    lagPump := secondMinIdx;
ELSIF runningCount = 1 THEN
    lagPump := 0;
END_IF;

// Preserve lead pump if no change occurred
IF NOT needSwitchLead AND NOT needInitialLead AND runningCount > 0 THEN
    leadPump := prevLeadPump;
END_IF;

// Update previous-cycle state
prevDemand := runningCount;
prevLeadPump := leadPump;
prevRunningCount := runningCount;
prevLagPump := lagPump;

END_FUNCTION_BLOCK