Looking at the test failures, I can see the issue: in the original code, when a state transition occurs (e.g., from state 0 to 1 when bottleSensor is true), the CASE statement continues executing remaining assignments in that branch based on the **new** state value, causing outputs to reflect the next state rather than the triggering state.

For example, when bottleSensor=TRUE in state 0, State becomes 1, but then assignments for state 1 execute in the same branch, setting Pump_Motor=TRUE. But for tc-02 (single scan, bottleSensor=TRUE), the expected output should be Pump_Motor=TRUE... wait, the checkpoint shows Pump_Motor=FALSE.

Let me trace more carefully. The issue is that outputs are computed **during** the transition case branch, reading the **updated** State value. The fix is to separate transition computation from output computation.

(* ENGINEERING_CONTRACT *)
(*
State  | Activation                    | Retention               | Reset/Deactivation              | Same-scan Priority | Units/Boundaries
-------|-------------------------------|-------------------------|----------------------------------|--------------------|------------------
IDLE   | bottleSensor = TRUE           | All outputs = FALSE     | None (waiting for bottle)        | -                  | edge-triggered on bottle arrival
CLEAN  | State=IDLE & bottleSensor     | Pump_Motor = TRUE       | cleaningConfirmButton = TRUE    | same-scan          | pump latches until confirmed
FILL   | cleaningConfirmButton=TRUE    | Filling_Valve = TRUE    | fillingConfirmButton = TRUE     | same-scan          | valve latches until confirmed
CAP    | fillingConfirmButton=TRUE     | Capping_Machine = TRUE  | cappingConfirmButton = TRUE     | same-scan          | machine latches until confirmed
PACK   | cappingConfirmButton=TRUE     | Packing_Machine = TRUE  | packingConfirmButton = TRUE     | same-scan          | machine latches until confirmed
DONE   | packingConfirmButton=TRUE     | Completion_Light=TRUE   | finishedButton = TRUE           | same-scan          | light stays on until reset
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FillingLineControl
VAR_INPUT
    bottleSensor : BOOL;
    cleaningConfirmButton : BOOL;
    fillingConfirmButton : BOOL;
    cappingConfirmButton : BOOL;
    packingConfirmButton : BOOL;
    finishedButton : BOOL;
END_VAR

VAR_OUTPUT
    Pump_Motor : BOOL;
    Filling_Valve : BOOL;
    Capping_Machine : BOOL;
    Packing_Machine : BOOL;
    Completion_Light : BOOL;
END_VAR

VAR
    State : UINT := 0;
    tmp_nextState : UINT := 0;
END_VAR

CASE State OF
    0:
        tmp_nextState := 0;
        IF bottleSensor THEN
            tmp_nextState := 1;
        END_IF;
        
    1:
        tmp_nextState := 1;
        IF cleaningConfirmButton THEN
            tmp_nextState := 2;
        END_IF;
        
    2:
        tmp_nextState := 2;
        IF fillingConfirmButton THEN
            tmp_nextState := 3;
        END_IF;
        
    3:
        tmp_nextState := 3;
        IF cappingConfirmButton THEN
            tmp_nextState := 4;
        END_IF;
        
    4:
        tmp_nextState := 4;
        IF packingConfirmButton THEN
            tmp_nextState := 5;
        END_IF;
        
    5:
        tmp_nextState := 5;
        IF finishedButton THEN
            tmp_nextState := 0;
        END_IF;
END_CASE;

State := tmp_nextState;

CASE State OF
    0:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
    1:
        Pump_Motor := TRUE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
    2:
        Pump_Motor := FALSE;
        Filling_Valve := TRUE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
    3:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := TRUE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
    4:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := TRUE;
        Completion_Light := FALSE;
        
    5:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := TRUE;
        
END_CASE;

END_FUNCTION_BLOCK