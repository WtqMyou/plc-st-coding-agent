FUNCTION_BLOCK FB
VAR_INPUT
    startBtn : BOOL;
    resetBtn : BOOL;
    doneSensor : BOOL;
    targetVol : REAL;
    flowVol : REAL;
END_VAR
VAR_OUTPUT
    valveOpen : BOOL;
    fillsToday : INT;
END_VAR
VAR
    start_prev : BOOL := FALSE;
    reset_prev : BOOL := FALSE;
    pendingConfirm : BOOL := FALSE;
    local_accumVol : REAL := 0.0;
    local_start_rise : BOOL;
    local_reset_rise : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
valveOpen: set on start_rise while previous output closed; hold while accumulated volume < targetVol;
            reset_rise priority closes immediately (S2,S5,S7,S8,S9).
pendingConfirm: set when accumulated volume reaches targetVol and valve closes; cleared by reset, new start,
            or confirmation after doneSensor = TRUE (Step4,S10,S13,S14).
fillsToday: +1 on pendingConfirm AND doneSensor, saturating at INT#32767; reset_rise sets 0;
            monotonic except reset (S1,S3,S4,S6,S14).
accumVol: REAL, mL; targetVol and flowVol REAL, mL; comparison uses >=.
*)
(* CONTRACT_RULES [] *)

local_start_rise := startBtn AND NOT start_prev;
local_reset_rise := resetBtn AND NOT reset_prev;

IF local_reset_rise THEN
    fillsToday := 0;
    local_accumVol := 0.0;
    valveOpen := FALSE;
    pendingConfirm := FALSE;
ELSE
    IF local_start_rise AND NOT valveOpen THEN
        local_accumVol := 0.0;
        valveOpen := TRUE;
        pendingConfirm := FALSE;
    END_IF;

    IF valveOpen THEN
        local_accumVol := local_accumVol + flowVol;
        IF local_accumVol >= targetVol THEN
            valveOpen := FALSE;
            pendingConfirm := TRUE;
        END_IF;
    END_IF;

    IF pendingConfirm AND doneSensor THEN
        IF fillsToday < INT#32767 THEN
            fillsToday := fillsToday + 1;
        END_IF;
        pendingConfirm := FALSE;
    END_IF;
END_IF;

start_prev := startBtn;
reset_prev := resetBtn;
END_FUNCTION_BLOCK