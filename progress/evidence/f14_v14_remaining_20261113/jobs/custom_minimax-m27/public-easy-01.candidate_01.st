(* ENGINEERING_CONTRACT
 * ============================================================================
 * State Machine: Automated Filling Line Control (6 states, sequential)
 * ============================================================================
 * | State      | Outputs Activated           | Retention    | Reset/Exit           |
 * |------------|-----------------------------|--------------|----------------------|
 * | IDLE       | none                        | -            | bottleSensor → CLEANING (PUB001) |
 * | CLEANING   | Pump_Motor:=TRUE            | hold until reset | cleaningConfirmButton → FILLING (PUB003) |
 * | FILLING    | Filling_Valve:=TRUE         | hold until reset | fillingConfirmButton → CAPPING (PUB003) |
 * | CAPPING    | Capping_Machine:=TRUE       | hold until reset | cappingConfirmButton → PACKING (PUB003) |
 * | PACKING    | Packing_Machine:=TRUE       | hold until reset | packingConfirmButton → COMPLETED (PUB005) |
 * | COMPLETED  | Completion_Light:=TRUE      | hold until reset | finishedButton → IDLE (PUB007) |
 * ============================================================================
 * Priority/Interlocks:
 *   - Physical direction rule: N/A (no opposite movements in this process)
 *   - Same-scan priority: outputs computed combinatorially from state, no priority
 *   - Button edge detection: R_TRIG on each confirm input to avoid repeat triggers
 *   - First scan behavior: outputs default to FALSE until first state transition
 *   - Boundary conditions: IDLE=0, COMPLETED=5 enum bounds, array indexing valid
 *   - Simultaneous buttons: not applicable (sequential process, one button per state)
 * ============================================================================
 * CONTRACT_RULES [{"kind": "hold_until_reset", "output": "Completion_Light", "set_input": "packingConfirmButton", "reset_input": "finishedButton"}]
 * ============================================================================
 *)

FUNCTION_BLOCK FillLineControl
VAR_INPUT
    bottleSensor          : BOOL;
    cleaningConfirmButton : BOOL;
    fillingConfirmButton  : BOOL;
    cappingConfirmButton  : BOOL;
    packingConfirmButton  : BOOL;
    finishedButton        : BOOL;
END_VAR
VAR_OUTPUT
    Pump_Motor      : BOOL;
    Filling_Valve   : BOOL;
    Capping_Machine : BOOL;
    Packing_Machine : BOOL;
    Completion_Light: BOOL;
END_VAR
VAR
    State        : UINT := 0;
    trg_bottle   : R_TRIG;
    trg_cleaning : R_TRIG;
    trg_filling  : R_TRIG;
    trg_capping  : R_TRIG;
    trg_packing  : R_TRIG;
    trg_finished : R_TRIG;
END_VAR

(* Constants for state identification *)
VAR CONSTANT
    STATE_IDLE      : UINT := 0;
    STATE_CLEANING  : UINT := 1;
    STATE_FILLING   : UINT := 2;
    STATE_CAPPING   : UINT := 3;
    STATE_PACKING   : UINT := 4;
    STATE_COMPLETED : UINT := 5;
END_VAR

(* Scan edge detectors *)
trg_bottle(CLK := bottleSensor);
trg_cleaning(CLK := cleaningConfirmButton);
trg_filling(CLK := fillingConfirmButton);
trg_capping(CLK := cappingConfirmButton);
trg_packing(CLK := packingConfirmButton);
trg_finished(CLK := finishedButton);

(* State machine transitions *)
CASE State OF
    STATE_IDLE:
        IF trg_bottle.Q THEN
            State := STATE_CLEANING;
        END_IF;

    STATE_CLEANING:
        IF trg_cleaning.Q THEN
            State := STATE_FILLING;
        END_IF;

    STATE_FILLING:
        IF trg_filling.Q THEN
            State := STATE_CAPPING;
        END_IF;

    STATE_CAPPING:
        IF trg_capping.Q THEN
            State := STATE_PACKING;
        END_IF;

    STATE_PACKING:
        IF trg_packing.Q THEN
            State := STATE_COMPLETED;
        END_IF;

    STATE_COMPLETED:
        IF trg_finished.Q THEN
            State := STATE_IDLE;
        END_IF;

END_CASE;

(* Output generation based on current state *)
Pump_Motor      := (State = STATE_CLEANING);
Filling_Valve   := (State = STATE_FILLING);
Capping_Machine := (State = STATE_CAPPING);
Packing_Machine := (State = STATE_PACKING);
Completion_Light:= (State = STATE_COMPLETED);

END_FUNCTION_BLOCK