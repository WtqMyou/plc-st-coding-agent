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
    hiActive : BOOL := FALSE;
    loActive : BOOL := FALSE;
END_VAR

error := FALSE;
status := WORD#0;

// Error condition: invalid limit configuration
IF loLevel >= hiLevel THEN
    error := TRUE;
    status := WORD#16#8001;
    hiActive := FALSE;
    loActive := FALSE;
    hiAlarm := FALSE;
    loAlarm := FALSE;
    RETURN;
END_IF;

// Error condition: hysteresis window too large
IF hystWindow >= (hiLevel - loLevel) THEN
    error := TRUE;
    status := WORD#16#8002;
    hiActive := FALSE;
    loActive := FALSE;
    hiAlarm := FALSE;
    loAlarm := FALSE;
    RETURN;
END_IF;

// High alarm with hysteresis
IF (Value > hiLevel) THEN
    hiActive := TRUE;
ELSIF (Value < (hiLevel - hystWindow)) THEN
    hiActive := FALSE;
END_IF;

// Low alarm with hysteresis
IF (Value < loLevel) THEN
    loActive := TRUE;
ELSIF (Value > (loLevel + hystWindow)) THEN
    loActive := FALSE;
END_IF;

// Assign outputs
hiAlarm := hiActive;
loAlarm := loActive;

END_FUNCTION_BLOCK