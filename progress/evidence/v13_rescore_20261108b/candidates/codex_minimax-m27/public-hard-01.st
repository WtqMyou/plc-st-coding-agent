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
    // Auto mode state machine
    autoState : INT;
    // Rising edge detection history
    prevValveAStart    : BOOL;
    prevValveBStart    : BOOL;
    prevValveCStart    : BOOL;
    prevValveDStart    : BOOL;
    prevMixMotorStart  : BOOL;
    prevAutoStart      : BOOL;
    // Rising edge results
    valveAStartEdge    : BOOL;
    valveBStartEdge    : BOOL;
    valveCStartEdge    : BOOL;
    valveDStartEdge    : BOOL;
    mixMotorStartEdge  : BOOL;
    autoStartEdge      : BOOL;
END_VAR

    // Auto state constants
    // 0=IDLE, 1=VALVE_A, 2=VALVE_B, 3=VALVE_C, 4=MIXING, 5=DISCHARGE

    // Rising edge detection
    valveAStartEdge   := valveAStart AND NOT prevValveAStart;
    valveBStartEdge   := valveBStart AND NOT prevValveBStart;
    valveCStartEdge   := valveCStart AND NOT prevValveCStart;
    valveDStartEdge   := valveDStart AND NOT prevValveDStart;
    mixMotorStartEdge := mixMotorStart AND NOT prevMixMotorStart;
    autoStartEdge     := autoStart AND NOT prevAutoStart;

    // Update edge detection history
    prevValveAStart   := valveAStart;
    prevValveBStart   := valveBStart;
    prevValveCStart   := valveCStart;
    prevValveDStart   := valveDStart;
    prevMixMotorStart := mixMotorStart;
    prevAutoStart     := autoStart;

    // Default outputs off (safety)
    valveARun   := FALSE;
    valveBRun   := FALSE;
    valveCRun   := FALSE;
    valveDRun   := FALSE;
    mixMotorRun := FALSE;

    // Emergency stop - all equipment stops immediately
    IF NOT estop THEN
        autoState := 0;
        RETURN;
    END_IF

    // Manual mode
    IF NOT opeMode THEN
        // Rising edge toggles for each device
        IF valveAStartEdge THEN
            valveARun := NOT valveARun;
        END_IF
        IF valveBStartEdge THEN
            valveBRun := NOT valveBRun;
        END_IF
        IF valveCStartEdge THEN
            valveCRun := NOT valveCRun;
        END_IF
        IF valveDStartEdge THEN
            valveDRun := NOT valveDRun;
        END_IF
        IF mixMotorStartEdge THEN
            mixMotorRun := NOT mixMotorRun;
        END_IF
    // Automatic mode
    ELSIF opeMode THEN
        CASE autoState OF
            0: // IDLE
                IF autoStartEdge THEN
                    autoState := 1;
                END_IF

            1: // Open Valve A
                valveARun := TRUE;
                IF levelSensor >= 50 THEN
                    valveARun := FALSE;
                    autoState := 2;
                END_IF

            2: // Open Valve B
                valveBRun := TRUE;
                IF levelSensor >= 80 THEN
                    valveBRun := FALSE;
                    IF processMode THEN
                        autoState := 3;
                    ELSE
                        autoState := 4;
                    END_IF;
                END_IF

            3: // Open Valve C (processMode=true)
                valveCRun := TRUE;
                IF levelSensor >= 100 THEN
                    valveCRun := FALSE;
                    autoState := 4;
                END_IF

            4: // Mixing
                mixMotorRun := TRUE;
                IF mixMotorComplete THEN
                    mixMotorRun := FALSE;
                    autoState := 5;
                END_IF

            5: // Discharge through Valve D
                valveDRun := TRUE;
                IF levelSensor <= 0 THEN
                    valveDRun := FALSE;
                    autoState := 0;
                END_IF
        END_CASE
    END_IF

END_FUNCTION_BLOCK