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
    tmpRising    : BOOL;
END_VAR

(*
ENGINEERING_CONTRACT
============================================================
Output | Activation         | Retention        | Reset/Deactivation    | Same-scan Priority | Units
-------|--------------------|------------------|-----------------------|--------------------|-------------
alarmHigh | tankLevel>=85.0   | hold until reset | rising(resetBtn) & tankLevel<85.0 | danger prioritizes over reset | BOOL latch
alarmLow  | tankLevel<=15.0   | hold until reset | rising(resetBtn) & tankLevel>15.0 | danger prioritizes over reset | BOOL latch
pumpRun   | inletPermit & !alarmHigh & !alarmLow | no retention | deasserts when alarm set | alarm blocks pump | combinational
outletValveOpen | !alarmLow    | no retention    | asserts when alarmLow=FALSE | alarmLow→closed | combinational inverse
============================================================
PUB: alarmHigh set by PUB001, alarmLow set by PUB003
PUB: alarmHigh reset by PUB005 (rising edge check), alarmLow reset by PUB005
PUB: pumpRun = inletPermit AND no alarms (PUB003, PUB007, PUB019, PUB026)
PUB: outletValveOpen = NOT alarmLow (PUB004, PUB027)
============================================================
*)

(* CONTRACT_RULES [] *)

tmpRising := resetBtn AND NOT prevResetBtn;

alarmHigh := alarmHigh OR (tankLevel >= 85.0);
IF tmpRising THEN
    IF tankLevel < 85.0 THEN
        alarmHigh := FALSE;
    END_IF;
END_IF;

alarmLow := alarmLow OR (tankLevel <= 15.0);
IF tmpRising THEN
    IF tankLevel > 15.0 THEN
        alarmLow := FALSE;
    END_IF;
END_IF;

prevResetBtn := resetBtn;

pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow;

outletValveOpen := NOT alarmLow;

END_FUNCTION_BLOCK