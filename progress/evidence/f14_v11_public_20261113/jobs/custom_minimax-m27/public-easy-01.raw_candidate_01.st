(* ENGINEERING_CONTRACT
+--------------------------------------------------------------------------------------+
| Output             | Activation                | Retention | Reset/Deactivation    | Units |
|--------------------|---------------------------|-----------|-----------------------|-------|
| Pump_Motor         | bottleSensor in IDLE      | Hold      | cleaningConfirmButton | BOOL  |
| Filling_Valve      | cleaningConfirmButton     | Hold      | fillingConfirmButton  | BOOL  |
| Capping_Machine    | fillingConfirmButton      | Hold      | cappingConfirmButton  | BOOL  |
| Packing_Machine    | cappingConfirmButton      | Hold      | packingConfirmButton  | BOOL  |
| Completion_Light   | packingConfirmButton      | Hold      | finishedButton        | BOOL  |
+--------------------------------------------------------------------------------------+
| State Machine: IDLE->CLEANING->FILLING->CAPPING->PACKING->COMPLETED->IDLE           |
| All confirm inputs use R_TRIG for edge detection (same-scan priority preserved).     |
| Outputs are combinational to their active state; no edge memory needed.              |
| finishedButton only resets from COMPLETED state (PUB008).                            |
+--------------------------------------------------------------------------------------+
*)
(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"Completion_Light","set_input":"packingConfirmButton","reset_input":"finishedButton"}] *)
FUNCTION_BLOCK BottleFillingLine
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
    eState : INT;
    IDLE      : INT := 0;
    CLEANING  : INT := 1;
    FILLING   : INT := 2;
    CAPPING   : INT := 3;
    PACKING   : INT := 4;
    COMPLETED : INT := 5;
    
    trigBottle   : R_TRIG;
    trigClean    : R_TRIG;
    trigFill     : R_TRIG;
    trigCap      : R_TRIG;
    trigPack     : R_TRIG;
    trigFinished : R_TRIG;
END_VAR

// Detect rising edges for all button inputs
trigBottle(CLK := bottleSensor);
trigClean(CLK := cleaningConfirmButton);
trigFill(CLK := fillingConfirmButton);
trigCap(CLK := cappingConfirmButton);
trigPack(CLK := packingConfirmButton);
trigFinished(CLK := finishedButton);

// State machine transitions
CASE eState OF
    IDLE:
        IF trigBottle.Q THEN
            eState := CLEANING;
        END_IF;
        
    CLEANING:
        IF trigClean.Q THEN
            eState := FILLING;
        END_IF;
        
    FILLING:
        IF trigFill.Q THEN
            eState := CAPPING;
        END_IF;
        
    CAPPING:
        IF trigCap.Q THEN
            eState := PACKING;
        END_IF;
        
    PACKING:
        IF trigPack.Q THEN
            eState := COMPLETED;
        END_IF;
        
    COMPLETED:
        IF trigFinished.Q THEN
            eState := IDLE;
        END_IF;
END_CASE;

// Output control based on current state
Pump_Motor       := (eState = CLEANING);
Filling_Valve    := (eState = FILLING);
Capping_Machine  := (eState = CAPPING);
Packing_Machine  := (eState = PACKING);
Completion_Light := (eState = COMPLETED);

END_FUNCTION_BLOCK