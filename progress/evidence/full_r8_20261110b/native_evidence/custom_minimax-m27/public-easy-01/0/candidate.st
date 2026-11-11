FUNCTION_BLOCK FB
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
    prev_Pump_Motor : BOOL;
    prev_Filling_Valve : BOOL;
    prev_Capping_Machine : BOOL;
    prev_Packing_Machine : BOOL;
    prev_Completion_Light : BOOL;
END_VAR

// Pump_Motor: latched by bottleSensor, reset by finishedButton
Pump_Motor := (prev_Pump_Motor OR bottleSensor) AND NOT finishedButton;

// Filling_Valve: starts when Pump_Motor was running and cleaning confirmed
Filling_Valve := (prev_Filling_Valve OR (prev_Pump_Motor AND cleaningConfirmButton)) AND NOT finishedButton;

// Capping_Machine: starts when Filling_Valve was running and filling confirmed
Capping_Machine := (prev_Capping_Machine OR (prev_Filling_Valve AND fillingConfirmButton)) AND NOT finishedButton;

// Packing_Machine: starts when Capping_Machine was running and capping confirmed
Packing_Machine := (prev_Packing_Machine OR (prev_Capping_Machine AND cappingConfirmButton)) AND NOT finishedButton;

// Completion_Light: starts when Packing_Machine was running and packing confirmed
Completion_Light := (prev_Completion_Light OR (prev_Packing_Machine AND packingConfirmButton)) AND NOT finishedButton;

// Update previous values for next scan cycle edge detection
prev_Pump_Motor := Pump_Motor;
prev_Filling_Valve := Filling_Valve;
prev_Capping_Machine := Capping_Machine;
prev_Packing_Machine := Packing_Machine;
prev_Completion_Light := Completion_Light;

END_FUNCTION_BLOCK