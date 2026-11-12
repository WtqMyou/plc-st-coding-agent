(* ENGINEERING_CONTRACT:
| State      | Activation                     | Retention     | Reset/Deactivation              | Same-scan Priority | Units/Boundaries |
|------------|--------------------------------|---------------|---------------------------------|--------------------|------------------|
| IDLE       | bottleSensor rising edge       | Hold          | Implicit on next state entry    | N/A                | Edge-triggered   |
| CLEANING   | Transition from IDLE           | Pump_Motor ON | cleaningConfirmButton edge      | FILLING higher     | State-based      |
| FILLING    | cleaningConfirmButton rising   | Filling_Valve ON | fillingConfirmButton edge    | CAPPING higher     | State-based      |
| CAPPING    | fillingConfirmButton rising    | Capping_Machine ON | cappingConfirmButton edge  | PACKAGING higher   | State-based      |
| PACKAGING  | cappingConfirmButton rising    | Packing_Machine ON | packingConfirmButton edge  | COMPLETE higher    | State-based      |
| COMPLETE   | packingConfirmButton rising    | Completion_Light ON | finishedButton edge         | IDLE lower         | State-based      |

PUB Clause Coverage:
- PUB001 (82-281): Sequential state machine with button confirmations
- PUB002 (282-303): Bottle sensor triggers cleaning pump
- PUB003 (304-416): cleaningConfirmButton advances to filling
- PUB004 (417-597): Filling valve operation and confirmation
- PUB005 (598-777): Capping machine operation and confirmation
- PUB006 (778-945): Packing machine operation and confirmation
- PUB007 (946-1127): Completion light activation
- PUB008 (1128-1307): finishedButton resets for next cycle

No unconditional latches beyond state retention per PUB clauses.
*)
FUNCTION_BLOCK FB_FillingLineControl
VAR_INPUT
    bottleSensor           : BOOL;
    cleaningConfirmButton  : BOOL;
    fillingConfirmButton   : BOOL;
    cappingConfirmButton   : BOOL;
    packingConfirmButton   : BOOL;
    finishedButton         : BOOL;
END_VAR
VAR_OUTPUT
    Pump_Motor             : BOOL;
    Filling_Valve          : BOOL;
    Capping_Machine        : BOOL;
    Packing_Machine        : BOOL;
    Completion_Light       : BOOL;
END_VAR
VAR
    eState : INT;
    tmp_Idle       : BOOL := TRUE;
    tmp_Cleaning   : BOOL := FALSE;
    tmp_Filling    : BOOL := FALSE;
    tmp_Capping    : BOOL := FALSE;
    tmp_Packaging  : BOOL := FALSE;
    tmp_Complete   : BOOL := FALSE;
    fbBottleSensor : R_TRIG;
    fbCleaningBtn  : R_TRIG;
    fbFillingBtn   : R_TRIG;
    fbCappingBtn   : R_TRIG;
    fbPackingBtn   : R_TRIG;
    fbFinishedBtn  : R_TRIG;
END_VAR

// Rising edge detectors
fbBottleSensor(CLK := bottleSensor);
fbCleaningBtn(CLK := cleaningConfirmButton);
fbFillingBtn(CLK := fillingConfirmButton);
fbCappingBtn(CLK := cappingConfirmButton);
fbPackingBtn(CLK := packingConfirmButton);
fbFinishedBtn(CLK := finishedButton);

// State machine
CASE eState OF
    0: // IDLE
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        tmp_Idle := TRUE;
        tmp_Cleaning := FALSE;
        tmp_Filling := FALSE;
        tmp_Capping := FALSE;
        tmp_Packaging := FALSE;
        tmp_Complete := FALSE;
        
        IF fbBottleSensor.Q THEN
            eState := 1;
        END_IF;

    1: // CLEANING
        tmp_Idle := FALSE;
        tmp_Cleaning := TRUE;
        Pump_Motor := TRUE;
        
        IF fbCleaningBtn.Q THEN
            eState := 2;
        END_IF;

    2: // FILLING
        tmp_Cleaning := FALSE;
        tmp_Filling := TRUE;
        Pump_Motor := FALSE;
        Filling_Valve := TRUE;
        
        IF fbFillingBtn.Q THEN
            eState := 3;
        END_IF;

    3: // CAPPING
        tmp_Filling := FALSE;
        tmp_Capping := TRUE;
        Filling_Valve := FALSE;
        Capping_Machine := TRUE;
        
        IF fbCappingBtn.Q THEN
            eState := 4;
        END_IF;

    4: // PACKAGING
        tmp_Capping := FALSE;
        tmp_Packaging := TRUE;
        Capping_Machine := FALSE;
        Packing_Machine := TRUE;
        
        IF fbPackingBtn.Q THEN
            eState := 5;
        END_IF;

    5: // COMPLETE
        tmp_Packaging := FALSE;
        tmp_Complete := TRUE;
        Packing_Machine := FALSE;
        Completion_Light := TRUE;
        
        IF fbFinishedBtn.Q THEN
            eState := 0;
        END_IF;

END_CASE;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)