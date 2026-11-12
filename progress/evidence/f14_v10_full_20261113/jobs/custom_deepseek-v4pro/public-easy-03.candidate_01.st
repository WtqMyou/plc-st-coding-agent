(* ENGINEERING_CONTRACT
   hiAlarm : SET on Value > hiLevel (PUB001), RESET on Value < hiLevel-hystWindow (PUB002), otherwise hold previous state.
   loAlarm : SET on Value < loLevel (PUB003), RESET on Value > loLevel+hystWindow (PUB004), otherwise hold previous state.
   error/status : SET 16#8001 when loLevel>=hiLevel and return (PUB005); SET 16#8002 when hystWindow>=hiLevel-loLevel and return (PUB006); cleared to FALSE/0 before checks.
   Priority : error checks run before alarm update; error returns preserve last alarm outputs.
   Boundaries : strict > and < for activation/deactivation; exact threshold equality holds current state. Negative hystWindow unspecified; applied as supplied.
   Units : REAL thresholds and values; status is WORD hex code.
*)
(* CONTRACT_RULES [] *)
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
END_VAR

    error := FALSE;
    status := 0;

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
        hiAlarm := TRUE;
    ELSIF Value < (hiLevel - hystWindow) THEN
        hiAlarm := FALSE;
    END_IF;

    IF Value < loLevel THEN
        loAlarm := TRUE;
    ELSIF Value > (loLevel + hystWindow) THEN
        loAlarm := FALSE;
    END_IF;

END_FUNCTION_BLOCK