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
END_VAR

// Parameter validation: loLevel must be less than hiLevel
IF loLevel >= hiLevel THEN
    error := TRUE;
    status := 16#8001;
    RETURN;
END_IF;

// Parameter validation: hystWindow must be less than the range between hiLevel and loLevel
IF hystWindow >= (hiLevel - loLevel) THEN
    error := TRUE;
    status := 16#8002;
    RETURN;
END_IF;

// High alarm: trigger when Value exceeds hiLevel, clear when below hiLevel minus hysteresis
IF Value > hiLevel THEN
    hiAlarm := TRUE;
ELSIF Value < (hiLevel - hystWindow) THEN
    hiAlarm := FALSE;
END_IF;

// Low alarm: trigger when Value falls below loLevel, clear when above loLevel plus hysteresis
IF Value < loLevel THEN
    loAlarm := TRUE;
ELSIF Value > (loLevel + hystWindow) THEN
    loAlarm := FALSE;
END_IF;

END_FUNCTION_BLOCK