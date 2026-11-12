FUNCTION_BLOCK AlarmWithHysteresis
VAR_OUTPUT
    hiAlarm : BOOL := FALSE;
    loAlarm : BOOL := FALSE;
    error   : BOOL := FALSE;
    status  : WORD := 16#0000;
END_VAR
VAR_INPUT
    Value      : REAL;
    hiLevel    : REAL;
    loLevel    : REAL;
    hystWindow : REAL;
END_VAR

// ENGINEERING_CONTRACT
// State retention: hiAlarm and loAlarm hold state across scans (level-triggered behavior)
// PUB001: hiAlarm activates at Value > hiLevel, deactivates at Value < hiLevel - hystWindow
// PUB002: loAlarm activates at Value < loLevel, deactivates at Value > loLevel + hystWindow
// PUB003: error=TRUE and status=16#8001 if loLevel >= hiLevel (checked first)
// PUB004: error=TRUE and status=16#8002 if hystWindow >= (hiLevel - loLevel)
// PUB005-PUB007: On error, set error=TRUE with status, exit without changing alarm outputs
// Same-scan priority: Error checks first, then hiAlarm, then loAlarm evaluation
// Units/boundaries: REAL comparison; error codes 16#8001, 16#8002; default status=16#0000

// CONTRACT_RULES: []
// No unconditional Boolean output latches; alarms are level-triggered based on current Value

// Error checking - highest priority
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

// No error; evaluate alarms based on current Value
error := FALSE;
status := 16#0000;

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