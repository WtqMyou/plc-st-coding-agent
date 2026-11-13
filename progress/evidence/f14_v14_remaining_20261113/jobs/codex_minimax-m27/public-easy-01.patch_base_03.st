(* ENGINEERING_CONTRACT *)
(*
  State machine for bottle filling line with 6 sequential states:
  - IDLE (0): No outputs active. Waits for bottleSensor TRUE → CLEANING.
  - CLEANING (1): Pump_Motor active. cleaningConfirmButton TRUE → FILLING.
  - FILLING (2): Filling_Valve active. fillingConfirmButton TRUE → CAPPING.
  - CAPPING (3): Capping_Machine active. cappingConfirmButton TRUE → PACKAGING.
  - PACKAGING (4): Packing_Machine active. packingConfirmButton TRUE → COMPLETED.
  - COMPLETED (5): Completion_Light active (retention). finishedButton TRUE → IDLE.
  
  Outputs: Pump_Motor(FILLING), Filling_Valve(FILLING), Capping_Machine(CAPPING),
           Packing_Machine(PACKAGING), Completion_Light(COMPLETED,hold_until_reset).
  Reset: finishedButton deactivates Completion_Light and returns to IDLE.
*)
(* CONTRACT_RULES [* kind=hold_until_reset, output=Completion_Light, set_input=packingConfirmButton, reset_input=finishedButton *] *)

FUNCTION_BLOCK FillingLineControl
VAR
    currentState : INT := 0;
END_VAR

CASE currentState OF
    0: // IDLE
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
        IF bottleSensor THEN
            currentState := 1;
        END_IF;

    1: // CLEANING
        Pump_Motor := TRUE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
        IF cleaningConfirmButton THEN
            currentState := 2;
        END_IF;

    2: // FILLING
        Pump_Motor := FALSE;
        Filling_Valve := TRUE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
        IF fillingConfirmButton THEN
            currentState := 3;
        END_IF;

    3: // CAPPING
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := TRUE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
        IF cappingConfirmButton THEN
            currentState := 4;
        END_IF;

    4: // PACKAGING
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := TRUE;
        Completion_Light := FALSE;
        
        IF packingConfirmButton THEN
            currentState := 5;
        END_IF;

    5: // COMPLETED
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := TRUE;
        
        IF finishedButton THEN
            currentState := 0;
        END_IF;
END_CASE;
END_FUNCTION_BLOCK