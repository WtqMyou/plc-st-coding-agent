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

(* ENGINEERING_CONTRACT
  hiAlarm: set while Value > hiLevel (PUB001); retained until Value < hiLevel-hystWindow (PUB001/PUB002).
  loAlarm: set while Value < loLevel (PUB001); retained until Value > loLevel+hystWindow (PUB001/PUB002).
  error/16#8001: loLevel >= hiLevel has priority, returns immediately after setting error and clearing alarms (PUB003).
  error/16#8002: hystWindow >= hiLevel-loLevel returns immediately after setting error and clearing alarms (PUB004).
  valid configuration: error := FALSE, status := 0, then both alarm paths are evaluated in the same scan.
  strict > and < comparisons only; equality retains the current alarm state. REAL boundaries and thresholds.
*)

(* CONTRACT_RULES [] *)

IF loLevel >= hiLevel THEN
    error := TRUE;
    status := 16#8001;
    hiAlarm := FALSE;
    loAlarm := FALSE;
    RETURN;
END_IF

IF hystWindow >= hiLevel - loLevel THEN
    error := TRUE;
    status := 16#8002;
    hiAlarm := FALSE;
    loAlarm := FALSE;
    RETURN;
END_IF

error := FALSE;
status := 0;

IF Value > hiLevel THEN
    hiAlarm := TRUE;
ELSIF Value < hiLevel - hystWindow THEN
    hiAlarm := FALSE;
END_IF

IF Value < loLevel THEN
    loAlarm := TRUE;
ELSIF Value > loLevel + hystWindow THEN
    loAlarm := FALSE;
END_IF

END_FUNCTION_BLOCK