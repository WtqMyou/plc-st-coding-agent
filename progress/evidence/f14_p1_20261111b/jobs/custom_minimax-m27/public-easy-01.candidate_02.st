PROGRAM AutomatedFillingLine
VAR
    bottleSensor           BOOL;
    cleaningConfirmButton  BOOL;
    fillingConfirmButton   BOOL;
    cappingConfirmButton   BOOL;
    packingConfirmButton   BOOL;
    finishedButton         BOOL;
    
    Pump_Motor             BOOL;
    Filling_Valve          BOOL;
    Capping_Machine        BOOL;
    Packing_Machine        BOOL;
    Completion_Light       BOOL;
    
    CurrentState           INT := 0;
END_VAR

CASE CurrentState OF
    0:
        Pump_Motor       := FALSE;
        Filling_Valve    := FALSE;
        Capping_Machine  := FALSE;
        Packing_Machine  := FALSE;
        Completion_Light := FALSE;
        
        IF bottleSensor THEN
            CurrentState := 1;
        END_IF

    1:
        Pump_Motor := TRUE;
        
        IF cleaningConfirmButton THEN
            CurrentState := 2;
        END_IF

    2:
        Filling_Valve := TRUE;
        
        IF fillingConfirmButton THEN
            CurrentState := 3;
        END_IF

    3:
        Capping_Machine := TRUE;
        
        IF cappingConfirmButton THEN
            CurrentState := 4;
        END_IF

    4:
        Packing_Machine := TRUE;
        
        IF packingConfirmButton THEN
            CurrentState := 5;
        END_IF

    5:
        Completion_Light := TRUE;
        
        IF finishedButton THEN
            CurrentState := 0;
        END_IF

END_CASE