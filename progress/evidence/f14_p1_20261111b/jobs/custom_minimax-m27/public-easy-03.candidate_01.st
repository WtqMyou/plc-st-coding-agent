FUNCTION_BLOCK AlarmHyst
VAR_INPUT
    Value      : REAL;   (* Current measured value *)
    hiLevel    : REAL;   (* High‑limit alarm threshold *)
    loLevel    : REAL;   (* Low‑limit alarm threshold  *)
    hystWindow : REAL;   (* Hysteresis window width    *)
END_VAR

VAR_OUTPUT
    hiAlarm : BOOL;   (* High‑limit alarm status *)
    loAlarm : BOOL;   (* Low‑limit alarm status  *)
    error   : BOOL;   (* FALSE = normal operation, TRUE = error detected *)
    status  : WORD;   (* Status / error code (0 = OK) *)
END_VAR

(* ---------------------------------------------------------------- *)
(*  Error detection (must be performed before any alarm logic)      *)
(* ---------------------------------------------------------------- *)
IF loLevel >= hiLevel THEN
    error   := TRUE;
    status  := WORD#16#8001;           (* 16#8001 : loLevel not lower than hiLevel *)
    hiAlarm := FALSE;
    loAlarm := FALSE;
    RETURN;                            (* leave the function block *)
END_IF

IF hystWindow >= (hiLevel - loLevel) THEN
    error   := TRUE;
    status  := WORD#16#8002;           (* 16#8002 : hystWindow too large *)
    hiAlarm := FALSE;
    loAlarm := FALSE;
    RETURN;
END_IF

(* ---------------------------------------------------------------- *)
(*  Normal operation – clear error flag and execute alarm logic     *)
(* ---------------------------------------------------------------- *)
error  := FALSE;
status := WORD#0;

(* ----- High‑limit alarm with hysteresis ------------------------- *)
(* Trigger:   Value > hiLevel                                       *)
(* Clear:     Value < hiLevel - hystWindow                          *)
IF Value > hiLevel THEN
    hiAlarm := TRUE;
ELSIF Value < (hiLevel - hystWindow) THEN
    hiAlarm := FALSE;
END_IF

(* ----- Low‑limit alarm with hysteresis -------------------------- *)
(* Trigger:   Value < loLevel                                       *)
(* Clear:     Value > loLevel + hystWindow                          *)
IF Value < loLevel THEN
    loAlarm := TRUE;
ELSIF Value > (loLevel + hystWindow) THEN
    loAlarm := FALSE;
END_IF

END_FUNCTION_BLOCK