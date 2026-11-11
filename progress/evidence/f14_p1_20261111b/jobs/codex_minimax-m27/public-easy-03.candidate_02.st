FUNCTION_BLOCK AlarmHandler
VAR_INPUT
    Value       : REAL;
    hiLevel     : REAL;
    loLevel     : REAL;
    hystWindow  : REAL;
END_VAR

VAR_OUTPUT
    hiAlarm     : BOOL;
    loAlarm     : BOOL;
    error       : BOOL;
    status      : WORD;
END_VAR

// Error checking
IF loLevel >= hiLevel THEN
    error := TRUE;
    status := 16#8001;
    RETURN;
END_IF

IF hystWindow >= (hiLevel - loLevel) THEN
    error := TRUE;
    status := 16#8002;
    RETURN;
END_IF

// No error - reset all outputs to defined state
error := FALSE;
status := 16#0000;
hiAlarm := FALSE;
loAlarm := FALSE;

// High alarm with hysteresis
// Trigger: Value > hiLevel
// Reset:   Value < hiLevel - hystWindow
IF Value > hiLevel THEN
    hiAlarm := TRUE;
END_IF

// Low alarm with hysteresis
// Trigger: Value < loLevel
// Reset:   Value > loLevel + hystWindow
IF Value < loLevel THEN
    loAlarm := TRUE;
END_IF

END_FUNCTION_BLOCK