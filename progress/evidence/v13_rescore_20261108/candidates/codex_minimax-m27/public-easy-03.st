FUNCTION_BLOCK FB
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

    // Parameter validation errors take priority
    IF loLevel >= hiLevel THEN
        error   := TRUE;
        status  := 16#8001;
        RETURN;
    END_IF

    IF hystWindow >= (hiLevel - loLevel) THEN
        error   := TRUE;
        status  := 16#8002;
        RETURN;
    END_IF

    // No error
    error  := FALSE;
    status := 16#0000;

    // High alarm with hysteresis
    // Trigger: Value > hiLevel
    // Reset:   Value < hiLevel - hystWindow
    IF Value > hiLevel THEN
        hiAlarm := TRUE;
    ELSIF Value < (hiLevel - hystWindow) THEN
        hiAlarm := FALSE;
    END_IF

    // Low alarm with hysteresis
    // Trigger: Value < loLevel
    // Reset:   Value > loLevel + hystWindow
    IF Value < loLevel THEN
        loAlarm := TRUE;
    ELSIF Value > (loLevel + hystWindow) THEN
        loAlarm := FALSE;
    END_IF

END_FUNCTION_BLOCK