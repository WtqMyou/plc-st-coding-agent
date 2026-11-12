FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel   : REAL;
    outletFlow  : REAL;
    inletPermit : BOOL;
    resetBtn    : BOOL;
END_VAR
VAR_OUTPUT
    pumpRun         : BOOL;
    alarmHigh       : BOOL;
    alarmLow        : BOOL;
    outletValveOpen : BOOL;
END_VAR
VAR
    prevResetBtn : BOOL := FALSE;
    latchHigh    : BOOL := FALSE;
    latchLow     : BOOL := FALSE;
END_VAR
VAR_TEMP
    risingReset : BOOL;
END_VAR

// Detect rising edge of reset button
risingReset := resetBtn AND NOT prevResetBtn;

// High level alarm: >= 85.0 sets immediately; falling below 85.0 clears only on rising reset
IF tankLevel >= 85.0 THEN
    latchHigh := TRUE;
ELSIF risingReset THEN
    latchHigh := FALSE;
END_IF;

// Low level alarm: <= 15.0 sets immediately; rising above 15.0 clears only on rising reset
IF tankLevel <= 15.0 THEN
    latchLow := TRUE;
ELSIF risingReset THEN
    latchLow := FALSE;
END_IF;

// Update latched states to outputs
alarmHigh := latchHigh;
alarmLow  := latchLow;

// Pump runs only when inlet permit is true AND both alarms are cleared
pumpRun := inletPermit AND (NOT alarmHigh) AND (NOT alarmLow);

// Outlet valve: open when low alarm is NOT latched
outletValveOpen := NOT alarmLow;

// Store button state for next scan edge detection
prevResetBtn := resetBtn;
END_FUNCTION_BLOCK