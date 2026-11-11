FUNCTION_BLOCK FB
VAR_INPUT
    Value : REAL;
    hiLevel : REAL;
    loLevel : REAL;
    hystWindow : REAL;
END_VAR
VAR_OUTPUT
    hiAlarm : BOOL;
    loAlarm : BOOL;
    error : BOOL;
    status : WORD;
END_VAR
VAR
    hiAlarmState : BOOL := FALSE;
    loAlarmState : BOOL := FALSE;
END_VAR

IF loLevel >= hiLevel THEN
    error := TRUE;
    status := 16#8001;
    hiAlarm := hiAlarmState;
    loAlarm := loAlarmState;
ELSIF hystWindow >= (hiLevel - loLevel) THEN
    error := TRUE;
    status := 16#8002;
    hiAlarm := hiAlarmState;
    loAlarm := loAlarmState;
ELSE
    error := FALSE;
    status := 0;

    IF Value > hiLevel THEN
        hiAlarmState := TRUE;
    ELSIF Value < (hiLevel - hystWindow) THEN
        hiAlarmState := FALSE;
    END_IF;

    IF Value < loLevel THEN
        loAlarmState := TRUE;
    ELSIF Value > (loLevel + hystWindow) THEN
        loAlarmState := FALSE;
    END_IF;

    hiAlarm := hiAlarmState;
    loAlarm := loAlarmState;
END_IF

END_FUNCTION_BLOCK