FUNCTION_BLOCK FB
VAR_INPUT
    estop: BOOL;
    opeMode: BOOL;
    valveAStart: BOOL;
    valveBStart: BOOL;
    valveCStart: BOOL;
    valveDStart: BOOL;
    mixMotorStart: BOOL;
    autoStart: BOOL;
    processMode: BOOL;
    levelSensor: INT;
    mixMotorComplete: BOOL;
END_VAR
VAR_OUTPUT
    valveARun: BOOL;
    valveBRun: BOOL;
    valveCRun: BOOL;
    valveDRun: BOOL;
    mixMotorRun: BOOL;
END_VAR
VAR
    manualValveA: BOOL := FALSE;
    manualValveB: BOOL := FALSE;
    manualValveC: BOOL := FALSE;
    manualValveD: BOOL := FALSE;
    manualMixMotor: BOOL := FALSE;
    autoStep: INT := 0;
    prevValveAStart: BOOL := FALSE;
    prevValveBStart: BOOL := FALSE;
    prevValveCStart: BOOL := FALSE;
    prevValveDStart: BOOL := FALSE;
    prevMixMotorStart: BOOL := FALSE;
    prevAutoStart: BOOL := FALSE;
    prevMixMotorComplete: BOOL := FALSE;
    prevOpeMode: BOOL := FALSE;
    edgeValveAStart: BOOL;
    edgeValveBStart: BOOL;
    edgeValveCStart: BOOL;
    edgeValveDStart: BOOL;
    edgeMixMotorStart: BOOL;
    edgeAutoStart: BOOL;
    edgeMixMotorComplete: BOOL;
    autoValveA: BOOL := FALSE;
    autoValveB: BOOL := FALSE;
    autoValveC: BOOL := FALSE;
    autoValveD: BOOL := FALSE;
    autoMixMotor: BOOL := FALSE;
END_VAR

edgeValveAStart := valveAStart AND NOT prevValveAStart;
edgeValveBStart := valveBStart AND NOT prevValveBStart;
edgeValveCStart := valveCStart AND NOT prevValveCStart;
edgeValveDStart := valveDStart AND NOT prevValveDStart;
edgeMixMotorStart := mixMotorStart AND NOT prevMixMotorStart;
edgeAutoStart := autoStart AND NOT prevAutoStart;
edgeMixMotorComplete := mixMotorComplete AND NOT prevMixMotorComplete;

IF estop THEN
    IF opeMode = FALSE THEN
        // Manual mode
        IF edgeValveAStart THEN manualValveA := NOT manualValveA; END_IF;
        IF edgeValveBStart THEN manualValveB := NOT manualValveB; END_IF;
        IF edgeValveCStart THEN manualValveC := NOT manualValveC; END_IF;
        IF edgeValveDStart THEN manualValveD := NOT manualValveD; END_IF;
        IF edgeMixMotorStart THEN manualMixMotor := NOT manualMixMotor; END_IF;
    ELSE
        // Automatic mode
        IF prevOpeMode = FALSE THEN
            autoStep := 0;
            autoValveA := FALSE;
            autoValveB := FALSE;
            autoValveC := FALSE;
            autoValveD := FALSE;
            autoMixMotor := FALSE;
        END_IF;

        CASE autoStep OF
            0: // Idle
                autoValveA := FALSE;
                autoValveB := FALSE;
                autoValveC := FALSE;
                autoValveD := FALSE;
                autoMixMotor := FALSE;
                IF edgeAutoStart THEN
                    autoValveA := TRUE;
                    autoStep := 1;
                END_IF;
            1: // Valve A open
                autoValveA := FALSE;
                autoValveB := FALSE;
                autoValveC := FALSE;
                autoValveD := FALSE;
                autoMixMotor := FALSE;
                autoValveA := TRUE;
                IF levelSensor >= 50 THEN
                    autoValveA := FALSE;
                    autoValveB := TRUE;
                    autoStep := 2;
                END_IF;
            2: // Valve B open
                autoValveA := FALSE;
                autoValveB := FALSE;
                autoValveC := FALSE;
                autoValveD := FALSE;
                autoMixMotor := FALSE;
                autoValveB := TRUE;
                IF levelSensor >= 80 THEN
                    autoValveB := FALSE;
                    IF processMode THEN
                        autoValveC := TRUE;
                        autoStep := 3;
                    ELSE
                        autoMixMotor := TRUE;
                        autoStep := 4;
                    END_IF;
                END_IF;
            3: // Valve C open
                autoValveA := FALSE;
                autoValveB := FALSE;
                autoValveC := FALSE;
                autoValveD := FALSE;
                autoMixMotor := FALSE;
                autoValveC := TRUE;
                IF levelSensor >= 100 THEN
                    autoValveC := FALSE;
                    autoMixMotor := TRUE;
                    autoStep := 4;
                END_IF;
            4: // Mixing motor running
                autoValveA := FALSE;
                autoValveB := FALSE;
                autoValveC := FALSE;
                autoValveD := FALSE;
                autoMixMotor := FALSE;
                autoMixMotor := TRUE;
                IF edgeMixMotorComplete THEN
                    autoMixMotor := FALSE;
                    autoValveD := TRUE;
                    autoStep := 0;
                END_IF;
        ELSE
            autoStep := 0;
            autoValveA := FALSE;
            autoValveB := FALSE;
            autoValveC := FALSE;
            autoValveD := FALSE;
            autoMixMotor := FALSE;
        END_CASE;
    END_IF;
ELSE
    // Emergency stop
    manualValveA := FALSE;
    manualValveB := FALSE;
    manualValveC := FALSE;
    manualValveD := FALSE;
    manualMixMotor := FALSE;
    autoStep := 0;
    autoValveA := FALSE;
    autoValveB := FALSE;
    autoValveC := FALSE;
    autoValveD := FALSE;
    autoMixMotor := FALSE;
END_IF;

// Assign outputs
IF estop = FALSE THEN
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;
ELSE
    IF opeMode = FALSE THEN
        valveARun := manualValveA;
        valveBRun := manualValveB;
        valveCRun := manualValveC;
        valveDRun := manualValveD;
        mixMotorRun := manualMixMotor;
    ELSE
        valveARun := autoValveA;
        valveBRun := autoValveB;
        valveCRun := autoValveC;
        valveDRun := autoValveD;
        mixMotorRun := autoMixMotor;
    END_IF;
END_IF;

// Update history
prevValveAStart := valveAStart;
prevValveBStart := valveBStart;
prevValveCStart := valveCStart;
prevValveDStart := valveDStart;
prevMixMotorStart := mixMotorStart;
prevAutoStart := autoStart;
prevMixMotorComplete := mixMotorComplete;
prevOpeMode := opeMode;

END_FUNCTION_BLOCK