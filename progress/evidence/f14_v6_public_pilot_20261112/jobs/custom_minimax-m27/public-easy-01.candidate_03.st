FUNCTION_BLOCK FillLineControl
VAR_INPUT
    bottleSensor           : BOOL;
    cleaningConfirmButton  : BOOL;
    fillingConfirmButton   : BOOL;
    cappingConfirmButton   : BOOL;
    packingConfirmButton   : BOOL;
    finishedButton         : BOOL;
END_VAR

VAR_OUTPUT
    Pump_Motor         : BOOL;
    Filling_Valve      : BOOL;
    Capping_Machine    : BOOL;
    Packing_Machine    : BOOL;
    Completion_Light   : BOOL;
END_VAR

VAR
    eState : INT;
    tmp_R_TRIG_cleaning : R_TRIG;
    tmp_R_TRIG_filling  : R_TRIG;
    tmp_R_TRIG_capping  : R_TRIG;
    tmp_R_TRIG_packing  : R_TRIG;
    tmp_R_TRIG_finished : R_TRIG;
END_VAR

VAR CONSTANT
    STATE_IDLE      : INT := 0;
    STATE_CLEANING  : INT := 1;
    STATE_FILLING   : INT := 2;
    STATE_CAPPING   : INT := 3;
    STATE_PACKING   : INT := 4;
END_VAR

(* ENGINEERING_CONTRACT
  State machine for automated filling line (5 states, linear sequence):
  +------------------+-------------------------------+-------------------+-------------------+---------------------------+
  | State            | Active Outputs                | Retention         | Deactivation      | Trigger                   |
  +------------------+-------------------------------+-------------------+-------------------+---------------------------+
  | IDLE (0)         | none                          | N/A               | N/A               | bottleSensor=TRUE         |
  | CLEANING (1)     | Pump_Motor=TRUE               | Hold until next   | Next state enter  | cleaningConfirmButton edge|
  | FILLING (2)      | Filling_Valve=TRUE            | Hold until next   | Next state enter  | fillingConfirmButton edge |
  | CAPPING (3)      | Capping_Machine=TRUE          | Hold until next   | Next state enter  | cappingConfirmButton edge |
  | PACKING (4)      | Packing_Machine=TRUE          | Hold until next   | Next state enter  | packingConfirmButton edge |
  +------------------+-------------------------------+-------------------+-------------------+---------------------------+
  Completion_Light: PUB007 latched output, set by packingConfirmButton edge,
                    reset by finishedButton edge. Independent of state machine.
  Priority: Same-scan parallel evaluation, outputs set per state at scan end.
  References: PUB003(cleaning pump start), PUB004(cleaningConfirmButton), 
              PUB005(fillingConfirmButton), PUB006(cappingConfirmButton),
              PUB007(packingConfirmButton triggers Completion_Light),
              PUB008(finishedButton reset).
*)
(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"Completion_Light","set_input":"packingConfirmButton","reset_input":"finishedButton"}] *)

tmp_R_TRIG_cleaning(CLK := cleaningConfirmButton);
tmp_R_TRIG_filling(CLK  := fillingConfirmButton);
tmp_R_TRIG_capping(CLK  := cappingConfirmButton);
tmp_R_TRIG_packing(CLK  := packingConfirmButton);
tmp_R_TRIG_finished(CLK := finishedButton);

CASE eState OF
    STATE_IDLE:
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        
        IF bottleSensor THEN
            eState := STATE_CLEANING;
        END_IF;

    STATE_CLEANING:
        Pump_Motor       := TRUE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        
        IF tmp_R_TRIG_cleaning.Q THEN
            eState := STATE_FILLING;
        END_IF;

    STATE_FILLING:
        Pump_Motor       := FALSE;
        Filling_Valve    := TRUE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        
        IF tmp_R_TRIG_filling.Q THEN
            eState := STATE_CAPPING;
        END_IF;

    STATE_CAPPING:
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := TRUE;
        Packing_Machine  := FALSE;
        
        IF tmp_R_TRIG_capping.Q THEN
            eState := STATE_PACKING;
        END_IF;

    STATE_PACKING:
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := TRUE;
        
        IF tmp_R_TRIG_packing.Q THEN
            eState := STATE_IDLE;
        END_IF;
END_CASE;

IF tmp_R_TRIG_packing.Q THEN
    Completion_Light := TRUE;
END_IF;

IF tmp_R_TRIG_finished.Q THEN
    Completion_Light := FALSE;
END_IF;

END_FUNCTION_BLOCK