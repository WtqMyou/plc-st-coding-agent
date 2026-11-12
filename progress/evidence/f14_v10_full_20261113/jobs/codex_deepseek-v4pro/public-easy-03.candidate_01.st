FUNCTION_BLOCK AlarmHandling
(* ENGINEERING_CONTRACT
  hiAlarm (PUB001): activate only when Value > hiLevel; hold across deadband until deactivation.
  hiAlarm deactivation (PUB001): deactivate only when Value < hiLevel - hystWindow (strict).
  loAlarm (PUB001): activate only when Value < loLevel; hold across deadband until deactivation.
  loAlarm deactivation (PUB001): deactivate only when Value > loLevel + hystWindow (strict).
  error/status (PUB006, PUB007): normal scan sets error:=FALSE and status:=0.
  Same-scan priority: loLevel >= hiLevel (16#8001) is checked first and invokes RETURN before alarm evaluation.
  hystWindow >= hiLevel - loLevel (16#8002) is checked next and suppresses normal alarm evaluation via ELSE.
  Retention: alarm outputs persist while inside their respective hysteresis deadband.
  Units: REAL values are dimensionless; status is a hexadecimal WORD code.
  Unspecified: behavior for NaN/Inf, negative hystWindow, and historical alarm state during error scans.
*)
(* CONTRACT_RULES [] *)
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
END_VAR

    error := FALSE;
    status := 0;

    IF loLevel >= hiLevel THEN
        error := TRUE;
        status := WORD#16#8001;
        RETURN;
    END_IF;

    IF hystWindow >= (hiLevel - loLevel) THEN
        error := TRUE;
        status := WORD#16#8002;
    ELSE
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
    END_IF;

END_FUNCTION_BLOCK