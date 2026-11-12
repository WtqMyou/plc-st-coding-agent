TYPE
    BottleState : (Idle := 0, Cleaning := 1, Filling := 2, Capping := 3, Packing := 4, Completed := 5);
END_TYPE

FUNCTION_BLOCK FillingLineControl
VAR_INPUT
    bottleSensor            : BOOL;
    cleaningConfirmButton   : BOOL;
    fillingConfirmButton    : BOOL;
    cappingConfirmButton    : BOOL;
    packingConfirmButton    : BOOL;
    finishedButton          : BOOL;
END_VAR
VAR_OUTPUT
    Pump_Motor              : BOOL;
    Filling_Valve           : BOOL;
    Capping_Machine         : BOOL;
    Packing_Machine         : BOOL;
    Completion_Light        : BOOL;
END_VAR
VAR
    state                       : BottleState := Idle;
    prevBottleSensor            : BOOL := FALSE;
    prevCleaningConfirmButton   : BOOL := FALSE;
    prevFillingConfirmButton    : BOOL := FALSE;
    prevCappingConfirmButton    : BOOL := FALSE;
    prevPackingConfirmButton    : BOOL := FALSE;
    prevFinishedButton          : BOOL := FALSE;
    edgeBottleSensor            : BOOL;
    edgeCleaningButton          : BOOL;
    edgeFillingButton           : BOOL;
    edgeCappingButton           : BOOL;
    edgePackingButton           : BOOL;
    edgeFinishedButton          : BOOL;
END_VAR
    edgeBottleSensor         := bottleSensor AND NOT prevBottleSensor;
    edgeCleaningButton       := cleaningConfirmButton AND NOT prevCleaningConfirmButton;
    edgeFillingButton        := fillingConfirmButton AND NOT prevFillingConfirmButton;
    edgeCappingButton        := cappingConfirmButton AND NOT prevCappingConfirmButton;
    edgePackingButton        := packingConfirmButton AND NOT prevPackingConfirmButton;
    edgeFinishedButton       := finishedButton AND NOT prevFinishedButton;

    prevBottleSensor         := bottleSensor;
    prevCleaningConfirmButton:= cleaningConfirmButton;
    prevFillingConfirmButton := fillingConfirmButton;
    prevCappingConfirmButton := cappingConfirmButton;
    prevPackingConfirmButton := packingConfirmButton;
    prevFinishedButton       := finishedButton;

    CASE TO_INT(state) OF
        0:
            Pump_Motor       := FALSE;
            Filling_Valve    := FALSE;
            Capping_Machine  := FALSE;
            Packing_Machine  := FALSE;
            Completion_Light := FALSE;
            IF edgeBottleSensor THEN
                state := Cleaning;
            END_IF

        1:
            Pump_Motor       := TRUE;
            Filling_Valve    := FALSE;
            Capping_Machine  := FALSE;
            Packing_Machine  := FALSE;
            Completion_Light := FALSE;
            IF edgeCleaningButton THEN
                state := Filling;
            END_IF

        2:
            Pump_Motor       := FALSE;
            Filling_Valve    := TRUE;
            Capping_Machine  := FALSE;
            Packing_Machine  := FALSE;
            Completion_Light := FALSE;
            IF edgeFillingButton THEN
                state := Capping;
            END_IF

        3:
            Pump_Motor       := FALSE;
            Filling_Valve    := FALSE;
            Capping_Machine  := TRUE;
            Packing_Machine  := FALSE;
            Completion_Light := FALSE;
            IF edgeCappingButton THEN
                state := Packing;
            END_IF

        4:
            Pump_Motor       := FALSE;
            Filling_Valve    := FALSE;
            Capping_Machine  := FALSE;
            Packing_Machine  := TRUE;
            Completion_Light := FALSE;
            IF edgePackingButton THEN
                state := Completed;
            END_IF

        5:
            Pump_Motor       := FALSE;
            Filling_Valve    := FALSE;
            Capping_Machine  := FALSE;
            Packing_Machine  := FALSE;
            Completion_Light := TRUE;
            IF edgeFinishedButton THEN
                state := Idle;
            END_IF
    END_CASE
END_FUNCTION_BLOCK