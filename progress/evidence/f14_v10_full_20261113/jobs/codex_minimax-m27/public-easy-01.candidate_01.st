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
VAR
    State : UINT := 0; // 0=IDLE, 1=CLEAN, 2=FILL, 3=CAP, 4=PACK, 5=DONE
END_VAR

// State machine logic
CASE State OF
    0: // IDLE - Waiting for bottle
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
        IF bottleSensor THEN
            State := 1;
        END_IF;
        
    1: // CLEAN - Cleaning pump running
        Pump_Motor := TRUE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
        IF cleaningConfirmButton THEN
            State := 2;
        END_IF;
        
    2: // FILL - Filling valve open
        Pump_Motor := FALSE;
        Filling_Valve := TRUE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
        IF fillingConfirmButton THEN
            State := 3;
        END_IF;
        
    3: // CAP - Capping machine running
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := TRUE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
        IF cappingConfirmButton THEN
            State := 4;
        END_IF;
        
    4: // PACK - Packing machine running
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := TRUE;
        Completion_Light := FALSE;
        
        IF packingConfirmButton THEN
            State := 5;
        END_IF;
        
    5: // DONE - Packaging complete, waiting for pickup
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := TRUE;
        
        IF finishedButton THEN
            State := 0;
        END_IF;
        
END_CASE;

END_FUNCTION_BLOCK