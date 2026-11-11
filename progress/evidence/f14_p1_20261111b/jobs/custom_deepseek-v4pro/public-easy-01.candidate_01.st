PROGRAM AutomatedFillingLine
VAR_INPUT
    bottleSensor         : BOOL;  // Bottle detection sensor
    cleaningConfirmButton : BOOL; // Cleaning completion confirmation
    fillingConfirmButton  : BOOL; // Filling completion confirmation
    cappingConfirmButton  : BOOL; // Capping completion confirmation
    packingConfirmButton  : BOOL; // Packaging completion confirmation
    finishedButton        : BOOL; // Bottle pickup confirmation
END_VAR
VAR_OUTPUT
    Pump_Motor        : BOOL; // Cleaning pump motor
    Filling_Valve     : BOOL; // Filling valve
    Capping_Machine   : BOOL; // Capping machine
    Packing_Machine   : BOOL; // Packing machine
    Completion_Light  : BOOL; // Packaging completion indicator
END_VAR
VAR
    state    : INT := 0; // 0=Idle, 1=Cleaning, 2=Filling, 3=Capping, 4=Packing, 5=Complete
    rBottle  : R_TRIG;
    rClean   : R_TRIG;
    rFill    : R_TRIG;
    rCap     : R_TRIG;
    rPack    : R_TRIG;
    rFinish  : R_TRIG;
END_VAR

// Edge detection for all digital signals
rBottle(CLK := bottleSensor);
rClean(CLK := cleaningConfirmButton);
rFill(CLK := fillingConfirmButton);
rCap(CLK := cappingConfirmButton);
rPack(CLK := packingConfirmButton);
rFinish(CLK := finishedButton);

CASE state OF
    // Idle: wait for bottle sensor
    0:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;

        IF rBottle.Q THEN
            state := 1;              // Start cleaning
            Pump_Motor := TRUE;
        END_IF;

    // Cleaning: run pump until operator confirms
    1:
        Pump_Motor := TRUE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;

        IF rClean.Q THEN
            state := 2;              // Cleaning done, start filling
            Pump_Motor := FALSE;
            Filling_Valve := TRUE;
        END_IF;

    // Filling: open valve until operator confirms
    2:
        Pump_Motor := FALSE;
        Filling_Valve := TRUE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;

        IF rFill.Q THEN
            state := 3;              // Filling done, start capping
            Filling_Valve := FALSE;
            Capping_Machine := TRUE;
        END_IF;

    // Capping: run capping machine until operator confirms
    3:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := TRUE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;

        IF rCap.Q THEN
            state := 4;              // Capping done, start packing
            Capping_Machine := FALSE;
            Packing_Machine := TRUE;
        END_IF;

    // Packing: run packing machine until operator confirms
    4:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := TRUE;
        Completion_Light := FALSE;

        IF rPack.Q THEN
            state := 5;              // Packing done, light indicator
            Packing_Machine := FALSE;
            Completion_Light := TRUE;
        END_IF;

    // Complete: wait for operator to pick up bottle
    5:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := TRUE;

        IF rFinish.Q THEN
            state := 0;              // Reset for next bottle
            Completion_Light := FALSE;
        END_IF;
END_CASE;