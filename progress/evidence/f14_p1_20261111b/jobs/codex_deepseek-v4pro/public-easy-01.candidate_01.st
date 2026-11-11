PROGRAM FillingLineControl
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
    State : INT := 0;
    bottleSensorR : R_TRIG;
    cleaningConfirmR : R_TRIG;
    fillingConfirmR : R_TRIG;
    cappingConfirmR : R_TRIG;
    packingConfirmR : R_TRIG;
    finishedR : R_TRIG;
END_VAR

bottleSensorR(CLK := bottleSensor);
cleaningConfirmR(CLK := cleaningConfirmButton);
fillingConfirmR(CLK := fillingConfirmButton);
cappingConfirmR(CLK := cappingConfirmButton);
packingConfirmR(CLK := packingConfirmButton);
finishedR(CLK := finishedButton);

Pump_Motor := FALSE;
Filling_Valve := FALSE;
Capping_Machine := FALSE;
Packing_Machine := FALSE;
Completion_Light := FALSE;

CASE State OF
    1:
        Pump_Motor := TRUE;
    2:
        Filling_Valve := TRUE;
    3:
        Capping_Machine := TRUE;
    4:
        Packing_Machine := TRUE;
    5:
        Completion_Light := TRUE;
END_CASE

IF State = 0 AND bottleSensorR.Q THEN
    State := 1;
ELSIF State = 1 AND cleaningConfirmR.Q THEN
    State := 2;
ELSIF State = 2 AND fillingConfirmR.Q THEN
    State := 3;
ELSIF State = 3 AND cappingConfirmR.Q THEN
    State := 4;
ELSIF State = 4 AND packingConfirmR.Q THEN
    State := 5;
ELSIF State = 5 AND finishedR.Q THEN
    State := 0;
END_IF