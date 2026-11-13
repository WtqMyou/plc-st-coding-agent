(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"alarmHigh","set_input":"tankLevel","reset_input":"resetBtn"},{"kind":"hold_until_reset","output":"alarmLow","set_input":"tankLevel","reset_input":"resetBtn"}] *)

(* ENGINEERING_CONTRACT
 * Input sampling: tankLevel, inletPermit, resetBtn sampled each scan
 * Output update: all outputs evaluated at end of same scan
 * 
 * | Output     | Activation              | Retention                  | Reset/Deactivation           | Priority      |
 * |------------|-------------------------|----------------------------|------------------------------|---------------|
 * | alarmHigh  | tankLevel >= 85.0       | Latched until safe+reset   | rising(resetBtn) & level<85  | Immediate     |
 * | alarmLow   | tankLevel <= 15.0       | Latched until safe+reset   | rising(resetBtn) & level>15  | Immediate     |
 * | pumpRun    | inletPermit & !alarms   | Held while conditions met  | Any alarm active or !permit  | Stop > Start  |
 * | outletValveOpen | !alarmLow           | Open unless low alarm held | alarmLow active closes it    | Inverse of alarmLow |
 * 
 * Boundaries: high=85.0, low=15.0 (inclusive thresholds per PUB001/PUB002)
 * Initial state: all outputs FALSE, prevBtn=FALSE
 * Scan behavior: same-scan evaluation of final state, edge detected via prev state
 *)

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
    prevAlarmHigh : BOOL := FALSE;
    prevAlarmLow  : BOOL := FALSE;
    tmpRisingReset : BOOL;
    tmpLevelHigh   : BOOL;
    tmpLevelLow    : BOOL;
END_VAR

    tmpRisingReset := resetBtn AND NOT prevResetBtn;
    tmpLevelHigh := (tankLevel >= 85.0);
    tmpLevelLow  := (tankLevel <= 15.0);

    IF tmpLevelHigh THEN
        alarmHigh := TRUE;
    ELSIF tmpRisingReset AND NOT tmpLevelHigh THEN
        alarmHigh := FALSE;
    END_IF;

    IF tmpLevelLow THEN
        alarmLow := TRUE;
    ELSIF tmpRisingReset AND NOT tmpLevelLow THEN
        alarmLow := FALSE;
    END_IF;

    IF NOT alarmHigh AND NOT alarmLow AND inletPermit THEN
        pumpRun := TRUE;
    ELSE
        pumpRun := FALSE;
    END_IF;

    outletValveOpen := NOT alarmLow;

    prevResetBtn := resetBtn;
    prevAlarmHigh := alarmHigh;
    prevAlarmLow := alarmLow;
END_FUNCTION_BLOCK