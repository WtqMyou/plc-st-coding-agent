PROGRAM FillingLineControl
VAR
    State : INT := 0;  // 0=Idle, 1=Cleaning, 2=Filling, 3=Capping, 4=Packing, 5=Complete
END_VAR

CASE State OF
    0:  // Idle - waiting for bottle
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
        IF bottleSensor THEN
            State := 1;
        END_IF
        
    1:  // Cleaning
        Pump_Motor := TRUE;
        
        IF cleaningConfirmButton THEN
            State := 2;
        END_IF
        
    2:  // Filling
        Pump_Motor := FALSE;
        Filling_Valve := TRUE;
        
        IF fillingConfirmButton THEN
            State := 3;
        END_IF
        
    3:  // Capping
        Filling_Valve := FALSE;
        Capping_Machine := TRUE;
        
        IF cappingConfirmButton THEN
            State := 4;
        END_IF
        
    4:  // Packing
        Capping_Machine := FALSE;
        Packing_Machine := TRUE;
        
        IF packingConfirmButton THEN
            State := 5;
        END_IF
        
    5:  // Complete - packaging finished, waiting for pickup
        Packing_Machine := FALSE;
        Completion_Light := TRUE;
        
        IF finishedButton THEN
            State := 0;
        END_IF
END_CASE