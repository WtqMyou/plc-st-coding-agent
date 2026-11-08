FUNCTION_BLOCK FB
VAR_INPUT
    Value      : REAL;
    hiLevel    : REAL;
    loLevel    : REAL;
    hystWindow : REAL;
END_VAR
VAR_OUTPUT
    hiAlarm : BOOL;
    loAlarm : BOOL;
    error   : BOOL;
    status  : WORD;
END_VAR
VAR
    highAlarmState : BOOL := FALSE;
    lowAlarmState  : BOOL := FALSE;
END_VAR

IF loLevel >= hiLevel THEN
    error          := TRUE;
    status         := 16#8001;
    hiAlarm        := FALSE;
    loAlarm        := FALSE;
    highAlarmState := FALSE;
    lowAlarmState  := FALSE;
ELSIF hystWindow >= (hiLevel - loLevel) THEN
    error          := TRUE;
    status         := 16#8002;
    hiAlarm        := FALSE;
    loAlarm        := FALSE;
    highAlarmState := FALSE;
    lowAlarmState  := FALSE;
ELSE
    error  := FALSE;
    status := 0;

    IF Value > hiLevel THEN
        highAlarmState := TRUE;
    ELSIF Value < (hiLevel - hystWindow) THEN
        highAlarmState := FALSE;
    END_IF;

    IF Value < loLevel THEN
        lowAlarmState := TRUE;
    ELSIF Value > (loLevel + hystWindow) THEN
        lowAlarmState := FALSE;
    END_IF;

    hiAlarm := highAlarmState;
    loAlarm := lowAlarmState;
END_IF

END_FUNCTION_BLOCK