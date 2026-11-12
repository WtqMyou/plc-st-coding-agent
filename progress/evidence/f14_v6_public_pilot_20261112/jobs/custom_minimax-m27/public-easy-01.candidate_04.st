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
    eState : INT := 0;
END_VAR

VAR CONSTANT
    STATE_IDLE      : INT := 0;
    STATE_CLEANING  : INT := 1;
    STATE_FILLING   : INT := 2;
    STATE_CAPPING   : INT := 3;
    STATE_PACKING   : INT := 4;
    STATE_COMPLETED : INT := 5;
END_VAR

(* ENGINEERING_CONTRACT
  Linear 6-state filling line with sequential transitions:
  +------------------+-------------------------------+-------------------+-------------------+---------------------------+
  | State            | Active Outputs                | Retention         | Deactivation      | Trigger                   |
  +------------------+-------------------------------+-------------------+-------------------+---------------------------+
  | IDLE (0)         | none                          | N/A               | N/A               | bottleSensor=TRUE         |
  | CLEANING (1)     | Pump_Motor=TRUE               | Hold until next   | Next state enter  | cleaningConfirmButton=TRUE|
  | FILLING (2)      | Filling_Valve=TRUE            | Hold until next   | Next state enter  | fillingConfirmButton=TRUE |
  | CAPPING (3)      | Capping_Machine=TRUE          | Hold until next   | Next state enter  | cappingConfirmButton=TRUE |
  | PACKING (4)      | Packing_Machine=TRUE          | Hold until next   | Next state enter  | packingConfirmButton=TRUE |
  | COMPLETED (5)    | Completion_Light=TRUE         | Hold until reset  | finishedButton=TRUE | packingConfirmButton=TRUE|
  +------------------+-------------------------------+-------------------+-------------------+---------------------------+
  Priority: Outputs set immediately on state entry before transition checks.
  References: PUB003(cleaning pump), PUB004(cleaningConfirmButton),
              PUB005(fillingConfirmButton), PUB006(cappingConfirmButton),
              PUB007(packingConfirmButton), PUB008(finishedButton reset).
*)
(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"Completion_Light","set_input":"packingConfirmButton","reset_input":"finishedButton"}] *)

CASE eState OF
    STATE_IDLE:
        IF bottleSensor THEN
            eState := STATE_CLEANING;
        END_IF;

    STATE_CLEANING:
        IF cleaningConfirmButton THEN
            eState := STATE_FILLING;
        END_IF;

    STATE_FILLING:
        IF fillingConfirmButton THEN
            eState := STATE_CAPPING;
        END_IF;

    STATE_CAPPING:
        IF cappingConfirmButton THEN
            eState := STATE_PACKING;
        END_IF;

    STATE_PACKING:
        IF packingConfirmButton THEN
            eState := STATE_COMPLETED;
        END_IF;

    STATE_COMPLETED:
        IF finishedButton THEN
            eState := STATE_IDLE;
        END_IF;
END_CASE;

Pump_Motor       := (eState = STATE_CLEANING);
Filling_Valve    := (eState = STATE_FILLING);
Capping_Machine  := (eState = STATE_CAPPING);
Packing_Machine  := (eState = STATE_PACKING);
Completion_Light := (eState = STATE_COMPLETED);

END_FUNCTION_BLOCK