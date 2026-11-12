FUNCTION_BLOCK FB
VAR_INPUT
    demand: INT;
    runHours: ARRAY[1..5] OF LINT;
    rotated: BOOL;
END_VAR
VAR_OUTPUT
    leadPump: INT;
    lagPump: INT;
    runningCount: INT;
END_VAR
VAR
    prevDemand: INT := 0;
    prevLeadPump: INT := 0;
    prevRunningCount: INT := 0;
    prevLagPump: INT := 0;
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
    clippedDemand: INT;
END_VAR

clippedDemand := demand;
IF clippedDemand < 0 THEN
    clippedDemand := 0;
ELSIF clippedDemand > 5 THEN
    clippedDemand := 5;
END_IF;

runningCount := clippedDemand;

needInitialLead := (prevDemand = 0) AND (runningCount > 0);
needRefreshLag := (runningCount > prevRunningCount) OR (leadPump <> prevLeadPump);

minHours := runHours[1];
minPumpIdx := 1;
FOR i := 2 TO 5 DO
    h := runHours[i];
    IF (h < minHours) OR ((h = minHours) AND (i < minPumpIdx)) THEN
        minHours := h;
        minPumpIdx := i;
    END_IF;
END_FOR;

IF leadPump >= 1 AND leadPump <= 5 THEN
    hoursDiff := runHours[leadPump] - minHours;
ELSE
    hoursDiff := 0;
END_IF;

needSwitchLead := (prevLeadPump <> 0) AND rotated AND (hoursDiff > 50);

IF runningCount = 0 THEN
    leadPump := 0;
    lagPump := 0;
ELSIF needSwitchLead THEN
    leadPump := minPumpIdx;
ELSIF needInitialLead THEN
    leadPump := minPumpIdx;
ELSE
    leadPump := prevLeadPump;
END_IF;

IF runningCount >= 2 THEN
    IF needRefreshLag THEN
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
    ELSE
        lagPump := prevLagPump;
    END_IF;
ELSE
    lagPump := 0;
END_IF;

prevDemand := clippedDemand;
prevLeadPump := leadPump;
prevRunningCount := runningCount;
prevLagPump := lagPump;

END_FUNCTION_BLOCK