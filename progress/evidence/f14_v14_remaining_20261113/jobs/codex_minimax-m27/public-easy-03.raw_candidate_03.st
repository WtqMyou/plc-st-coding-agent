(*
ENGINEERING_CONTRACT
===================
hiAlarm activation: Value > hiLevel (PUB001)
hiAlarm retention: remains TRUE until Value < hiLevel - hystWindow (PUB001)
loAlarm activation: Value < loLevel (PUB003)
loAlarm retention: remains TRUE until Value > loLevel + hystWindow (PUB003)
error activation: loLevel >= hiLevel → status=16#8001 (PUB005)
error activation: hystWindow >= (hiLevel - loLevel) → status=16#8002 (PUB006)
reset/deactivation: error conditions return early, alarms retain prior state
same-scan priority: error checks precede alarm logic; no output overlap conflicts
units/boundaries: REAL comparisons with explicit thresholds; strict > and <

CONTRACT_RULES []
*)

FUNCTION_BLOCK AlarmHysteresis
VAR_INPUT
    Value       : REAL;
    hiLevel     : REAL;
    loLevel     : REAL;
    hystWindow  : REAL;
END_VAR
VAR_OUTPUT
    hiAlarm     : BOOL := FALSE;
    loAlarm     : BOOL := FALSE;
    error       : BOOL := FALSE;
    status      : WORD := 16#0000;
END_VAR
VAR
    tmpError    : BOOL := FALSE;
    tmpStatus   : WORD := 16#0000;
END_VAR

IF loLevel >= hiLevel THEN
    tmpError := TRUE;
    tmpStatus := 16#8001;
END_IF;

IF hystWindow >= (hiLevel - loLevel) THEN
    tmpError := TRUE;
    tmpStatus := 16#8002;
END_IF;

error := tmpError;
status := tmpStatus;

IF NOT tmpError THEN
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