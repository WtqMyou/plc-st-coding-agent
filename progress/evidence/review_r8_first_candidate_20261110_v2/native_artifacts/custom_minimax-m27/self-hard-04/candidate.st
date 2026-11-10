FUNCTION_BLOCK FB
VAR_INPUT
    demand    : INT;
    runHours  : ARRAY[1..5] OF LINT;
    rotated   : BOOL;
END_VAR
VAR_OUTPUT
    leadPump      : INT := 0;
    lagPump       : INT := 0;
    runningCount  : INT := 0;
END_VAR
VAR
    prevLeadPump      : INT := 0;
    prevRunningCount  : INT := 0;
    minHours          : LINT;
    minPump           : INT;
    bestLagHours      : LINT;
    bestLagPump       : INT;
    i                 : INT;
END_VAR

// Clip demand to [0, 5]
runningCount := demand;
IF runningCount < 0 THEN
    runningCount := 0;
ELSIF runningCount > 5 THEN
    runningCount := 5;
END_IF;

// Find global minimum (hours, pumpId)
minHours := runHours[1];
minPump := 1;
FOR i := 2 TO 5 DO
    IF runHours[i] < minHours OR (runHours[i] = minHours AND i < minPump) THEN
        minHours := runHours[i];
        minPump := i;
    END_IF;
END_FOR;

// Lead pump selection
IF runningCount = 0 THEN
    leadPump := 0;
    lagPump  := 0;
ELSIF prevRunningCount = 0 THEN
    // Demand just became positive - select based on minimum hours
    leadPump := minPump;
ELSIF rotated AND (runHours[leadPump] - minHours > 50) THEN
    // Hysteresis: switch only if main pump hours exceed global min by >50
    leadPump := minPump;
END_IF;

// Lag pump selection: only on initial, lead change, or count increase
IF runningCount >= 2 THEN
    IF lagPump = 0 OR leadPump <> prevLeadPump OR runningCount > prevRunningCount THEN
        bestLagHours := LINT#16#7FFFFFFFFFFFFFFF;
        bestLagPump  := 0;
        FOR i := 1 TO 5 DO
            IF i <> leadPump THEN
                IF runHours[i] < bestLagHours OR (runHours[i] = bestLagHours AND i < bestLagPump) THEN
                    bestLagHours := runHours[i];
                    bestLagPump  := i;
                END_IF;
            END_IF;
        END_FOR;
        lagPump := bestLagPump;
    END_IF;
ELSE
    lagPump := 0;
END_IF;

// Update history for next scan
prevLeadPump     := leadPump;
prevRunningCount := runningCount;
END_FUNCTION_BLOCK