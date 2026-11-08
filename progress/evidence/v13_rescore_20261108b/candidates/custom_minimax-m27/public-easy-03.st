FUNCTION_BLOCK FB
VAR_INPUT
    Value       : REAL;
    hiLevel     : REAL;
    loLevel     : REAL;
    hystWindow  : REAL;
END_VAR
VAR_OUTPUT
    hiAlarm : BOOL := FALSE;
    loAlarm : BOOL := FALSE;
    error   : BOOL := FALSE;
    status  : WORD := 0;
END_VAR

error := FALSE;
status := 0;

IF loLevel >= hiLevel THEN
    error := TRUE;
    status := 16#8001;
    hiAlarm := FALSE;
    loAlarm := FALSE;
    RETURN;
END_IF

IF hystWindow >= (hiLevel - loLevel) THEN
    error := TRUE;
    status := 16#8002;
    hiAlarm := FALSE;
    loAlarm := FALSE;
    RETURN;
END_IF

IF Value > hiLevel THEN
    hiAlarm := TRUE;
ELSIF Value < (hiLevel - hystWindow) THEN
    hiAlarm := FALSE;
END_IF

IF Value < loLevel THEN
    loAlarm := TRUE;
ELSIF Value > (loLevel + hystWindow) THEN
    loAlarm := FALSE;
END_IF

END_FUNCTION_BLOCK