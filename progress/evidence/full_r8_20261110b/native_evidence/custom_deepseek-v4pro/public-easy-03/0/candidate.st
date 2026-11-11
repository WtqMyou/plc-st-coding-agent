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
    hiAlarmState : BOOL;
    loAlarmState : BOOL;
END_VAR

IF loLevel >= hiLevel THEN
    error := TRUE;
    status := WORD#16#8001;
ELSE
    IF hystWindow >= (hiLevel - loLevel) THEN
        error := TRUE;
        status := WORD#16#8002;
    ELSE
        error := FALSE;
        status := WORD#0;
        
        IF Value > hiLevel THEN
            hiAlarmState := TRUE;
        ELSIF Value < hiLevel - hystWindow THEN
            hiAlarmState := FALSE;
        END_IF
        
        IF Value < loLevel THEN
            loAlarmState := TRUE;
        ELSIF Value > loLevel + hystWindow THEN
            loAlarmState := FALSE;
        END_IF
    END_IF
END_IF

hiAlarm := hiAlarmState;
loAlarm := loAlarmState;

END_FUNCTION_BLOCK