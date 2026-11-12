FUNCTION_BLOCK AlarmHysteresis
VAR_INPUT
    Value       : REAL;
    hiLevel     : REAL;
    loLevel     : REAL;
    hystWindow  : REAL;
END_VAR
VAR_OUTPUT
    hiAlarm     : BOOL;
    loAlarm     : BOOL;
    error       : BOOL;
    status      : WORD;
END_VAR
VAR
    hiAlarmLatched : BOOL;
    loAlarmLatched : BOOL;
END_VAR
// ENGINEERING_CONTRACT
// PUB001: High alarm hiAlarm activates when Value > hiLevel
// PUB001: High alarm hiAlarm exits when Value < hiLevel - hystWindow
// PUB002: Low alarm loAlarm activates when Value < loLevel
// PUB002: Low alarm loAlarm exits when Value > loLevel + hystWindow
// PUB003: loLevel >= hiLevel -> error=TRUE, status=16#8001, exit
// PUB004: hystWindow >= (hiLevel - loLevel) -> error=TRUE, status=16#8002, exit
// PUB005/PUB006/PUB007: Hysteresis latch retains state across scans; alarm holds
//   until value crosses opposite boundary; outputs reflect latched state
// Output retention: alarms retain state between scans via internal latches
// Priority: error check first, then alarm evaluation with no same-scan conflict
// Units: REAL thresholds, WORD status codes in hexadecimal
// (* CONTRACT_RULES [{"kind":"hold_until_reset","output":"hiAlarm","set_input":"Value","reset_input":null},{"kind":"hold_until_reset","output":"loAlarm","set_input":"Value","reset_input":null}] *)
BEGIN
    // Default safe state
    hiAlarm := FALSE;
    loAlarm := FALSE;
    error := FALSE;
    status := 16#0000;

    // Error: loLevel >= hiLevel
    IF loLevel >= hiLevel THEN
        error := TRUE;
        status := 16#8001;
        RETURN;
    END_IF

    // Error: hystWindow >= (hiLevel - loLevel)
    IF hystWindow >= (hiLevel - loLevel) THEN
        error := TRUE;
        status := 16#8002;
        RETURN;
    END_IF

    // High alarm with hysteresis: set >, clear <
    IF Value > hiLevel THEN
        hiAlarmLatched := TRUE;
    ELSIF Value < (hiLevel - hystWindow) THEN
        hiAlarmLatched := FALSE;
    END_IF

    // Low alarm with hysteresis: set <, clear >
    IF Value < loLevel THEN
        loAlarmLatched := TRUE;
    ELSIF Value > (loLevel + hystWindow) THEN
        loAlarmLatched := FALSE;
    END_IF

    // Assign latched alarm states to outputs
    hiAlarm := hiAlarmLatched;
    loAlarm := loAlarmLatched;
END_FUNCTION_BLOCK