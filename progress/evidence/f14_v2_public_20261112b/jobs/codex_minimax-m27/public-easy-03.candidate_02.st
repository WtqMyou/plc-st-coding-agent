FUNCTION_BLOCK AlarmHysteresis
VAR_INPUT
    Value       : REAL;
    hiLevel     : REAL;
    loLevel     : REAL;
    hystWindow  : REAL;
END_VAR

VAR_OUTPUT
    hiAlarm     : BOOL := FALSE;
    loAlarm     : BOOL := FALSE;
    error       : BOOL;
    status      : WORD := 16#0000;
END_VAR

    // Error: loLevel must be less than hiLevel
    IF loLevel >= hiLevel THEN
        error := TRUE;
        status := 16#8001;
        RETURN;
    END_IF

    // Error: hystWindow must be less than the deviation range
    IF hystWindow >= (hiLevel - loLevel) THEN
        error := TRUE;
        status := 16#8002;
        RETURN;
    END_IF

    // No error - only clear error flag, preserve status
    error := FALSE;

    // High alarm with hysteresis
    // Trigger: Value > hiLevel
    // Release: Value < hiLevel - hystWindow
    IF Value > hiLevel THEN
        hiAlarm := TRUE;
    ELSIF Value < (hiLevel - hystWindow) THEN
        hiAlarm := FALSE;
    END_IF

    // Low alarm with hysteresis
    // Trigger: Value < loLevel
    // Release: Value > loLevel + hystWindow
    IF Value < loLevel THEN
        loAlarm := TRUE;
    ELSIF Value > (loLevel + hystWindow) THEN
        loAlarm := FALSE;
    END_IF

END_FUNCTION_BLOCK