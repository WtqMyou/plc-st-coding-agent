FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel : REAL;
    outletFlow : REAL;
    inletPermit : BOOL;
    resetBtn : BOOL;
END_VAR
VAR_OUTPUT
    pumpRun : BOOL;
    alarmHigh : BOOL;
    alarmLow : BOOL;
    outletValveOpen : BOOL;
END_VAR
VAR
    highLatched : BOOL := FALSE;
    lowLatched : BOOL := FALSE;
    prevResetBtn : BOOL := FALSE;
    tmp_resetRising : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   alarmHigh/alarmLow: set immediately at respective threshold, then latch.
   Activation: high >= 85.0, low <= 15.0 (REAL percent).
   Retention: remain latched when level returns to normal until reset.
   Reset: resetBtn rising edge clears each latch only if its danger is absent.
   Same-scan priority: danger condition overrides reset for the affected alarm.
   pumpRun: active only when inletPermit AND no alarm latched.
   outletValveOpen: inverse of low alarm; outletFlow is unused observation input.
*)

(* CONTRACT_RULES [] *)

tmp_resetRising := resetBtn AND NOT prevResetBtn;

IF tankLevel >= 85.0 THEN
    highLatched := TRUE;
ELSIF tmp_resetRising THEN
    highLatched := FALSE;
END_IF;

IF tankLevel <= 15.0 THEN
    lowLatched := TRUE;
ELSIF tmp_resetRising THEN
    lowLatched := FALSE;
END_IF;

alarmHigh := highLatched;
alarmLow := lowLatched;
pumpRun := inletPermit AND NOT highLatched AND NOT lowLatched;
outletValveOpen := NOT lowLatched;

prevResetBtn := resetBtn;

END_FUNCTION_BLOCK