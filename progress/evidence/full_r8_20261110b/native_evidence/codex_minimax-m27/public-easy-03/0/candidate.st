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

// Priority R5: loLevel >= hiLevel
IF loLevel >= hiLevel THEN
    error := TRUE;
    status := 16#8001;
    RETURN;
END_IF

// Priority R6: hystWindow >= (hiLevel - loLevel)
IF hystWindow >= (hiLevel - loLevel) THEN
    error := TRUE;
    status := 16#8002;
    RETURN;
END_IF

// No error - clear error flags
error := FALSE;
status := 16#0000;

// R1: Value > hiLevel
IF Value > hiLevel THEN
    hiAlarm := TRUE;
END_IF

// R2: Value < hiLevel - hystWindow
IF Value < (hiLevel - hystWindow) THEN
    hiAlarm := FALSE;
END_IF

// R3: Value < loLevel
IF Value < loLevel THEN
    loAlarm := TRUE;
END_IF

// R4: Value > loLevel + hystWindow
IF Value > (loLevel + hystWindow) THEN
    loAlarm := FALSE;
END_IF

END_FUNCTION_BLOCK