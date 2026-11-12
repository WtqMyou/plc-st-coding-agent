FUNCTION_BLOCK AlarmHysteresis
VAR_INPUT
    Value      : REAL;
    hiLevel    : REAL;
    loLevel    : REAL;
    hystWindow : REAL;
END_VAR
VAR_OUTPUT
    hiAlarm : BOOL := FALSE;
    loAlarm : BOOL := FALSE;
    error   : BOOL := FALSE;
    status  : WORD := 16#0000;
END_VAR
VAR
END_VAR

(* Error detection *)
IF loLevel >= hiLevel THEN
    error  := TRUE;
    status := 16#8001;
    hiAlarm := FALSE;
    loAlarm := FALSE;
    RETURN;
END_IF

IF hystWindow >= (hiLevel - loLevel) THEN
    error  := TRUE;
    status := 16#8002;
    hiAlarm := FALSE;
    loAlarm := FALSE;
    RETURN;
END_IF

(* No error *)
error  := FALSE;
status := 16#0000;

(* High alarm with hysteresis *)
IF Value > hiLevel THEN
    hiAlarm := TRUE;
ELSIF Value < (hiLevel - hystWindow) THEN
    hiAlarm := FALSE;
END_IF;

(* Low alarm with hysteresis *)
IF Value < loLevel THEN
    loAlarm := TRUE;
ELSIF Value > (loLevel + hystWindow) THEN
    loAlarm := FALSE;
END_IF;

END_FUNCTION_BLOCK