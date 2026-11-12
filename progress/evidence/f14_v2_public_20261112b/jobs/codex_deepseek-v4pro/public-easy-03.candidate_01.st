FUNCTION_BLOCK AlarmHandling
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
    hiAlarmState : BOOL;
    loAlarmState : BOOL;
END_VAR

BEGIN
    hiAlarm := FALSE;
    loAlarm := FALSE;
    error := FALSE;
    status := 16#0000;

    IF loLevel >= hiLevel THEN
        error := TRUE;
        status := 16#8001;
        RETURN;
    END_IF;

    IF hystWindow >= (hiLevel - loLevel) THEN
        error := TRUE;
        status := 16#8002;
        RETURN;
    END_IF;

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
END_FUNCTION_BLOCK