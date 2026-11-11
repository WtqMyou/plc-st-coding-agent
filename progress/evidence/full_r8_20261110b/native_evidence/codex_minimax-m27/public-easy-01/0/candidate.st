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
    prevPumpMotor : BOOL;
    prevFillingValve : BOOL;
    prevCappingMachine : BOOL;
    prevPackingMachine : BOOL;
    prevCompletionLight : BOOL;
END_VAR

Pump_Motor := (Pump_Motor OR bottleSensor) AND NOT finishedButton;
Filling_Valve := (Filling_Valve OR (prevPumpMotor AND cleaningConfirmButton)) AND NOT finishedButton;
Capping_Machine := (Capping_Machine OR (prevFillingValve AND fillingConfirmButton)) AND NOT finishedButton;
Packing_Machine := (Packing_Machine OR (prevCappingMachine AND cappingConfirmButton)) AND NOT finishedButton;
Completion_Light := (Completion_Light OR (prevPackingMachine AND packingConfirmButton)) AND NOT finishedButton;

prevPumpMotor := Pump_Motor;
prevFillingValve := Filling_Valve;
prevCappingMachine := Capping_Machine;
prevPackingMachine := Packing_Machine;
prevCompletionLight := Completion_Light;

END_FUNCTION_BLOCK