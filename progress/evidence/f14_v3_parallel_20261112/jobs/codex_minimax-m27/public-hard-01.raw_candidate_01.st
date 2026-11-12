FUNCTION_BLOCK MaterialProportioningControl
VAR_INPUT
    estop           : BOOL;
    opeMode         : BOOL;
    valveAStart     : BOOL;
    valveBStart     : BOOL;
    valveCStart     : BOOL;
    valveDStart     : BOOL;
    mixMotorStart   : BOOL;
    autoStart       : BOOL;
    processMode     : BOOL;
    levelSensor     : INT;
    mixMotorComplete: BOOL;
END_VAR

VAR_OUTPUT
    valveARun       : BOOL;
    valveBRun       : BOOL;
    valveCRun       : BOOL;
    valveDRun       : BOOL;
    mixMotorRun     : BOOL;
END_VAR

VAR
    prevValveAStart     : BOOL := FALSE;
    prevValveBStart     : BOOL := FALSE;
    prevValveCStart     : BOOL := FALSE;
    prevValveDStart     : BOOL := FALSE;
    prevMixMotorStart   : BOOL := FALSE;
    prevAutoStart       : BOOL := FALSE;
    autoState           : INT := 0;
    autoRunning         : BOOL := FALSE;
END_VAR

// Emergency Stop - stops all equipment immediately
IF NOT estop THEN
    valveARun   := FALSE;
    valveBRun   := FALSE;
    valveCRun   := FALSE;
    valveDRun   := FALSE;
    mixMotorRun := FALSE;
    autoRunning := FALSE;
    autoState   := 0;
    RETURN;
END_IF

// Manual Mode
IF NOT opeMode THEN
    // Rising edge detection for Valve A toggle
    IF valveAStart AND NOT prevValveAStart THEN
        valveARun := NOT valveARun;
    END_IF;
    prevValveAStart := valveAStart;

    // Rising edge detection for Valve B toggle
    IF valveBStart AND NOT prevValveBStart THEN
        valveBRun := NOT valveBRun;
    END_IF;
    prevValveBStart := valveBStart;

    // Rising edge detection for Valve C toggle
    IF valveCStart AND NOT prevValveCStart THEN
        valveCRun := NOT valveCRun;
    END_IF;
    prevValveCStart := valveCStart;

    // Rising edge detection for Valve D toggle
    IF valveDStart AND NOT prevValveDStart THEN
        valveDRun := NOT valveDRun;
    END_IF;
    prevValveDStart := valveDStart;

    // Rising edge detection for Mixing Motor toggle
    IF mixMotorStart AND NOT prevMixMotorStart THEN
        mixMotorRun := NOT mixMotorRun;
    END_IF;
    prevMixMotorStart := mixMotorStart;

// Automatic Mode
ELSE
    // Rising edge detection for autoStart
    IF autoStart AND NOT prevAutoStart AND NOT autoRunning THEN
        autoRunning := TRUE;
        autoState   := 1;
    END_IF;
    prevAutoStart := autoStart;

    // State machine for automatic process flow
    IF autoRunning THEN
        CASE autoState OF
            1: // Open Valve A
                valveARun := TRUE;
                IF levelSensor >= 50 THEN
                    valveARun := FALSE;
                    autoState := 2;
                END_IF;

            2: // Open Valve B, wait for level 80cm
                valveBRun := TRUE;
                IF levelSensor >= 80 THEN
                    valveBRun := FALSE;
                    IF processMode THEN
                        autoState := 3;
                    ELSE
                        autoState := 4;
                    END_IF;
                END_IF;

            3: // Open Valve C (processMode=true), wait for level 100cm
                valveCRun := TRUE;
                IF levelSensor >= 100 THEN
                    valveCRun := FALSE;
                    autoState := 4;
                END_IF;

            4: // Start mixing motor
                mixMotorRun := TRUE;
                IF mixMotorComplete THEN
                    mixMotorRun := FALSE;
                    autoState := 5;
                END_IF;

            5: // Open Valve D, end automatic process
                valveDRun  := TRUE;
                autoRunning := FALSE;
                autoState   := 0;
        END_CASE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK