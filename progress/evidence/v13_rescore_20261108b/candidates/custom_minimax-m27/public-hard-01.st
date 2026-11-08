FUNCTION_BLOCK FB
VAR_INPUT
    estop            : BOOL;
    opeMode          : BOOL;
    valveAStart      : BOOL;
    valveBStart      : BOOL;
    valveCStart      : BOOL;
    valveDStart      : BOOL;
    mixMotorStart    : BOOL;
    autoStart        : BOOL;
    processMode      : BOOL;
    levelSensor      : INT;
    mixMotorComplete : BOOL;
END_VAR
VAR_OUTPUT
    valveARun    : BOOL;
    valveBRun    : BOOL;
    valveCRun    : BOOL;
    valveDRun    : BOOL;
    mixMotorRun  : BOOL;
END_VAR
VAR
    autoState         : INT := 0;
    prevValveAStart   : BOOL := FALSE;
    prevValveBStart   : BOOL := FALSE;
    prevValveCStart   : BOOL := FALSE;
    prevValveDStart   : BOOL := FALSE;
    prevMixMotorStart : BOOL := FALSE;
    prevAutoStart     : BOOL := FALSE;
    prevMixMotorComplete : BOOL := FALSE;
END_VAR

    // Emergency stop: highest priority, stop all equipment immediately
    IF NOT estop THEN
        valveARun   := FALSE;
        valveBRun   := FALSE;
        valveCRun   := FALSE;
        valveDRun   := FALSE;
        mixMotorRun := FALSE;
        autoState   := 0;
        prevAutoStart            := autoStart;
        prevMixMotorComplete     := mixMotorComplete;
        prevValveAStart          := valveAStart;
        prevValveBStart          := valveBStart;
        prevValveCStart          := valveCStart;
        prevValveDStart          := valveDStart;
        prevMixMotorStart        := mixMotorStart;
    ELSE
        // Mode transition reset
        IF opeMode THEN
            IF prevValveAStart OR prevValveBStart OR prevValveCStart OR prevValveDStart OR prevMixMotorStart THEN
                autoState := 0;
            END_IF
            prevValveAStart   := FALSE;
            prevValveBStart   := FALSE;
            prevValveCStart   := FALSE;
            prevValveDStart   := FALSE;
            prevMixMotorStart := FALSE;
        ELSE
            // Manual mode: rising edge toggles
            IF valveAStart AND NOT prevValveAStart THEN
                valveARun := NOT valveARun;
            END_IF;
            IF valveBStart AND NOT prevValveBStart THEN
                valveBRun := NOT valveBRun;
            END_IF;
            IF valveCStart AND NOT prevValveCStart THEN
                valveCRun := NOT valveCRun;
            END_IF;
            IF valveDStart AND NOT prevValveDStart THEN
                valveDRun := NOT valveDRun;
            END_IF;
            IF mixMotorStart AND NOT prevMixMotorStart THEN
                mixMotorRun := NOT mixMotorRun;
            END_IF;
        END_IF

        // Automatic mode state machine
        IF opeMode THEN
            // State 0: Idle, wait for autoStart rising edge
            IF autoState = 0 THEN
                valveARun   := FALSE;
                valveBRun   := FALSE;
                valveCRun   := FALSE;
                valveDRun   := FALSE;
                mixMotorRun := FALSE;
                IF autoStart AND NOT prevAutoStart THEN
                    autoState := 1;
                END_IF;

            // State 1: Fill with valve A
            ELSIF autoState = 1 THEN
                valveBRun   := FALSE;
                valveCRun   := FALSE;
                valveDRun   := FALSE;
                mixMotorRun := FALSE;
                IF levelSensor >= 50 THEN
                    valveARun := FALSE;
                    autoState := 2;
                ELSE
                    valveARun := TRUE;
                END_IF;

            // State 2: Fill with valve B
            ELSIF autoState = 2 THEN
                valveARun   := FALSE;
                valveCRun   := FALSE;
                valveDRun   := FALSE;
                mixMotorRun := FALSE;
                IF levelSensor >= 80 THEN
                    valveBRun := FALSE;
                    IF processMode THEN
                        autoState := 3;
                    ELSE
                        autoState := 4;
                    END_IF;
                ELSE
                    valveBRun := TRUE;
                END_IF;

            // State 3: Fill with valve C (processMode = true)
            ELSIF autoState = 3 THEN
                valveARun   := FALSE;
                valveBRun   := FALSE;
                valveDRun   := FALSE;
                mixMotorRun := FALSE;
                IF levelSensor >= 100 THEN
                    valveCRun := FALSE;
                    autoState := 4;
                ELSE
                    valveCRun := TRUE;
                END_IF;

            // State 4: Mixing
            ELSIF autoState = 4 THEN
                valveARun   := FALSE;
                valveBRun   := FALSE;
                valveCRun   := FALSE;
                valveDRun   := FALSE;
                mixMotorRun := TRUE;
                IF mixMotorComplete AND NOT prevMixMotorComplete THEN
                    mixMotorRun := FALSE;
                    valveDRun   := TRUE;
                    autoState   := 5;
                END_IF;

            // State 5: Discharge complete, wait for next autoStart
            ELSIF autoState = 5 THEN
                valveARun   := FALSE;
                valveBRun   := FALSE;
                valveCRun   := FALSE;
                mixMotorRun := FALSE;
                valveDRun   := TRUE;
                IF autoStart AND NOT prevAutoStart THEN
                    valveDRun := FALSE;
                    autoState := 0;
                END_IF;
            END_IF;
        END_IF;
    END_IF;

    // Update edge detection history
    prevValveAStart   := valveAStart;
    prevValveBStart   := valveBStart;
    prevValveCStart   := valveCStart;
    prevValveDStart   := valveDStart;
    prevMixMotorStart := mixMotorStart;
    prevAutoStart     := autoStart;
    prevMixMotorComplete := mixMotorComplete;

END_FUNCTION_BLOCK