FUNCTION_BLOCK FB

(* ENGINEERING_CONTRACT
   alarms: latch immediately on their own danger condition, retain until a new
           resetBtn rising edge occurs while the condition is gone; dangerous
           condition has priority on the same scan.
   reset edge: detected from resetBtn TRUE and previous scan resetBtn FALSE;
                prevResetBtn is updated at the end of every scan.
   pumpRun: combinational after alarm update; TRUE iff inletPermit AND no alarm.
   outletValveOpen: combinational; TRUE iff low alarm is FALSE.
   tankLevel units: percent; thresholds are >= 85.0 for high and <= 15.0 for low.
   outletFlow: observed only, does not affect outputs.
*)

VAR_INPUT
    tankLevel : REAL;    (* 0..100 % *)
    outletFlow : REAL;   (* m3/h, reserved observation input *)
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
    local_prevResetBtn : BOOL := FALSE;
    local_risingReset : BOOL;
    tmp_highState : BOOL := FALSE;
    tmp_lowState : BOOL := FALSE;
END_VAR

(* CONTRACT_RULES [] *)

local_risingReset := resetBtn AND NOT local_prevResetBtn;

(* High alarm: danger condition sets and latches. *)
IF tankLevel >= 85.0 THEN
    tmp_highState := TRUE;
ELSIF local_risingReset THEN
    tmp_highState := FALSE;
END_IF;

(* Low alarm: danger condition sets and latches. *)
IF tankLevel <= 15.0 THEN
    tmp_lowState := TRUE;
ELSIF local_risingReset THEN
    tmp_lowState := FALSE;
END_IF;

alarmHigh := tmp_highState;
alarmLow := tmp_lowState;

pumpRun := inletPermit AND NOT alarmHigh AND NOT alarmLow;
outletValveOpen := NOT alarmLow;

local_prevResetBtn := resetBtn;

END_FUNCTION_BLOCK