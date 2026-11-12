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
    step : INT := 0;
END_VAR

CASE step OF
    0:
        IF bottleSensor THEN
            step := 1;
        END_IF;

    1:
        IF cleaningConfirmButton THEN
            step := 2;
        END_IF;

    2:
        IF fillingConfirmButton THEN
            step := 3;
        END_IF;

    3:
        IF cappingConfirmButton THEN
            step := 4;
        END_IF;

    4:
        IF packingConfirmButton THEN
            step := 5;
        END_IF;

    5:
        IF finishedButton THEN
            step := 0;
        END_IF;
END_CASE;

Pump_Motor := (step = 1);
Filling_Valve := (step = 2);
Capping_Machine := (step = 3);
Packing_Machine := (step = 4);
Completion_Light := (step = 5);

END_FUNCTION_BLOCK