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
    currentState : INT := 0;
END_VAR

CASE currentState OF
    0:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
        IF bottleSensor THEN
            currentState := 1;
        END_IF;
        
    1:
        Pump_Motor := TRUE;
        
        IF cleaningConfirmButton THEN
            currentState := 2;
        END_IF;
        
    2:
        Pump_Motor := FALSE;
        Filling_Valve := TRUE;
        
        IF fillingConfirmButton THEN
            currentState := 3;
        END_IF;
        
    3:
        Filling_Valve := FALSE;
        Capping_Machine := TRUE;
        
        IF cappingConfirmButton THEN
            currentState := 4;
        END_IF;
        
    4:
        Capping_Machine := FALSE;
        Packing_Machine := TRUE;
        
        IF packingConfirmButton THEN
            currentState := 5;
        END_IF;
        
    5:
        Packing_Machine := FALSE;
        Completion_Light := TRUE;
        
        IF finishedButton THEN
            currentState := 0;
        END_IF;
END_CASE;
END_FUNCTION_BLOCK