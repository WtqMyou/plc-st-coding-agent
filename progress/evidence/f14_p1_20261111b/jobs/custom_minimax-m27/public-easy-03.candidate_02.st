FUNCTION_BLOCK AlarmHyst
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

VAR RETAIN
    errorOccurred : BOOL := FALSE;
    statusValue   : WORD := WORD#0;
    hiAlarmPrev   : BOOL := FALSE;
    loAlarmPrev   : BOOL := FALSE;
END_VAR

(* ---------------------------------------------------------------- *)
(*  Error detection - latch error state                             *)
(* ---------------------------------------------------------------- *)
IF loLevel >= hiLevel THEN
    error         := TRUE;
    status        := WORD#16#8001;
    errorOccurred := TRUE;
    statusValue   := WORD#16#8001;
    hiAlarm       := FALSE;
    loAlarm       := FALSE;
    RETURN;
END_IF

IF hystWindow >= (hiLevel - loLevel) THEN
    error         := TRUE;
    status        := WORD#16#8002;
    errorOccurred := TRUE;
    statusValue   := WORD#16#8002;
    hiAlarm       := FALSE;
    loAlarm       := FALSE;
    RETURN;
END_IF

(* ---------------------------------------------------------------- *)
(*  Normal operation                                                *)
(* ---------------------------------------------------------------- *)
(* Clear latched error when configuration is valid                  *)
errorOccurred := FALSE;
statusValue   := WORD#0;

(* ----- High‑limit alarm with hysteresis ------------------------- *)
IF Value > hiLevel THEN
    hiAlarmPrev := TRUE;
ELSIF Value < (hiLevel - hystWindow) THEN
    hiAlarmPrev := FALSE;
END_IF

(* ----- Low‑limit alarm with hysteresis -------------------------- *)
IF Value < loLevel THEN
    loAlarmPrev := TRUE;
ELSIF Value > (loLevel + hystWindow) THEN
    loAlarmPrev := FALSE;
END_IF

(* Update outputs *)
error   := errorOccurred;
status  := statusValue;
hiAlarm := hiAlarmPrev;
loAlarm := loAlarmPrev;

END_FUNCTION_BLOCK