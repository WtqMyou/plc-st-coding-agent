FUNCTION_BLOCK MaterialProportioningControl
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
    State          : INT;
    StateNext      : INT;
    autoStarted    : BOOL;
    valveAToggled  : BOOL;
    valveBToggled  : BOOL;
    valveCToggled  : BOOL;
    valveDToggled  : BOOL;
    motorToggled   : BOOL;
    lastAutoStart  : BOOL;
    lastValveAStart : BOOL;
    lastValveBStart : BOOL;
    lastValveCStart : BOOL;
    lastValveDStart : BOOL;
    lastMixMotorStart : BOOL;
END_VAR

VAR CONSTANT
    AUTO_IDLE       : INT := 0;
    AUTO_FILL_A     : INT := 1;
    AUTO_FILL_B     : INT := 2;
    AUTO_FILL_C     : INT := 3;
    AUTO_MIXING     : INT := 4;
    AUTO_DRAIN      : INT := 5;
END_VAR

    lastAutoStart := autoStart;
    lastValveAStart := valveAStart;
    lastValveBStart := valveBStart;
    lastValveCStart := valveCStart;
    lastValveDStart := valveDStart;
    lastMixMotorStart := mixMotorStart;

    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;

    IF NOT estop THEN
        State := AUTO_IDLE;
        autoStarted := FALSE;
        valveAToggled := FALSE;
        valveBToggled := FALSE;
        valveCToggled := FALSE;
        valveDToggled := FALSE;
        motorToggled := FALSE;
        RETURN;
    END_IF

    IF NOT opeMode THEN
        State := AUTO_IDLE;
        autoStarted := FALSE;

        IF valveAStart AND NOT lastValveAStart THEN
            valveAToggled := NOT valveAToggled;
        END_IF

        IF valveBStart AND NOT lastValveBStart THEN
            valveBToggled := NOT valveBToggled;
        END_IF

        IF valveCStart AND NOT lastValveCStart THEN
            valveCToggled := NOT valveCToggled;
        END_IF

        IF valveDStart AND NOT lastValveDStart THEN
            valveDToggled := NOT valveDToggled;
        END_IF

        IF mixMotorStart AND NOT lastMixMotorStart THEN
            motorToggled := NOT motorToggled;
        END_IF

        valveARun := valveAToggled;
        valveBRun := valveBToggled;
        valveCRun := valveCToggled;
        valveDRun := valveDToggled;
        mixMotorRun := motorToggled;

        RETURN;
    END_IF

    CASE State OF
        AUTO_IDLE:
            autoStarted := FALSE;
            valveAToggled := FALSE;
            valveBToggled := FALSE;
            valveCToggled := FALSE;
            valveDToggled := FALSE;
            motorToggled := FALSE;
            IF autoStart AND NOT lastAutoStart THEN
                State := AUTO_FILL_A;
            END_IF;

        AUTO_FILL_A:
            valveARun := TRUE;
            IF levelSensor >= 50 THEN
                valveARun := FALSE;
                State := AUTO_FILL_B;
            END_IF;

        AUTO_FILL_B:
            valveBRun := TRUE;
            IF levelSensor >= 80 THEN
                valveBRun := FALSE;
                IF NOT processMode THEN
                    State := AUTO_MIXING;
                ELSE
                    State := AUTO_FILL_C;
                END_IF;
            END_IF;

        AUTO_FILL_C:
            valveCRun := TRUE;
            IF levelSensor >= 100 THEN
                valveCRun := FALSE;
                State := AUTO_MIXING;
            END_IF;

        AUTO_MIXING:
            mixMotorRun := TRUE;
            IF mixMotorComplete THEN
                mixMotorRun := FALSE;
                State := AUTO_DRAIN;
            END_IF;

        AUTO_DRAIN:
            valveDRun := TRUE;

    END_CASE;

END_FUNCTION_BLOCK