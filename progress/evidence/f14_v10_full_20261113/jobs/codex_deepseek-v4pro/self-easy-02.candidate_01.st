(*
ENGINEERING_CONTRACT
- alarmHigh: active if tankLevel >= 85.0; once active, retains until a rising resetBtn occurs while tankLevel < 85.0; danger on the same scan as reset wins.
- alarmLow: active if tankLevel <= 15.0; once active, retains until a rising resetBtn occurs while tankLevel > 15.0; danger on the same scan as reset wins.
- reset edge: rising only when resetBtn is TRUE and the stored previous value is FALSE; holding resetBtn generates no additional resets.
- pumpRun: evaluated after alarm updates, TRUE only when inletPermit, !alarmHigh, and !alarmLow.
- outletValveOpen: evaluated after alarm updates, equals !alarmLow.
- outletFlow: observation input only, not used.
- Units: tankLevel is REAL percent; thresholds are inclusive as stated.
*)
(* CONTRACT_RULES [] *)
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
    prevResetBtn : BOOL := FALSE;
    tmp_highDanger : BOOL;
    tmp_lowDanger : BOOL;
    tmp_resetRise : BOOL;
END_VAR

tmp_resetRise := resetBtn AND NOT prevResetBtn;

tmp_highDanger := tankLevel >= 85.0;
tmp_lowDanger := tankLevel <= 15.0;

alarmHigh := tmp_highDanger OR (alarmHigh AND NOT tmp_resetRise);
alarmLow := tmp_lowDanger OR (alarmLow AND NOT tmp_resetRise);

pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow;
outletValveOpen := NOT alarmLow;

prevResetBtn := resetBtn;

END_FUNCTION_BLOCK