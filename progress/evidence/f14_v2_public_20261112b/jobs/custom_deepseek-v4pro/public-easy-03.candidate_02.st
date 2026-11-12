FUNCTION_BLOCK AlarmHandler
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
END_VAR

BEGIN
    THIS^.error := FALSE;
    THIS^.status := 0;

    IF loLevel >= hiLevel THEN
        THIS^.error := TRUE;
        THIS^.status := 16#8001;
        RETURN;
    ELSIF hystWindow >= (hiLevel - loLevel) THEN
        THIS^.error := TRUE;
        THIS^.status := 16#8002;
        RETURN;
    END_IF;

    // High limit alarm with hysteresis
    IF Value > hiLevel THEN
        hiAlarm := TRUE;
    ELSIF Value < (hiLevel - hystWindow) THEN
        hiAlarm := FALSE;
    END_IF;

    // Low limit alarm with hysteresis
    IF Value < loLevel THEN
        loAlarm := TRUE;
    ELSIF Value > (loLevel + hystWindow) THEN
        loAlarm := FALSE;
    END_IF;
END_FUNCTION_BLOCK