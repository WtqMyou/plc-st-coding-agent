FUNCTION_BLOCK FB
VAR_INPUT
    estop : BOOL;
    opeMode : BOOL;
    valveAStart : BOOL;
    valveBStart : BOOL;
    valveCStart : BOOL;
    valveDStart : BOOL;
    mixMotorStart : BOOL;
    autoStart : BOOL;
    processMode : BOOL;
    levelSensor : INT;
    mixMotorComplete : BOOL;
END_VAR
VAR_OUTPUT
    valveARun : BOOL;
    valveBRun : BOOL;
    valveCRun : BOOL;
    valveDRun : BOOL;
    mixMotorRun : BOOL;
END_VAR
VAR
    valveARunCmd : BOOL := FALSE;
    valveBRunCmd : BOOL := FALSE;
    valveCRunCmd : BOOL := FALSE;
    valveDRunCmd : BOOL := FALSE;
    mixMotorRunCmd : BOOL := FALSE;

    autoStep : INT := 0;

    valveAStartPrev : BOOL := FALSE;
    valveBStartPrev : BOOL := FALSE;
    valveCStartPrev : BOOL := FALSE;
    valveDStartPrev : BOOL := FALSE;
    mixMotorStartPrev : BOOL := FALSE;
    autoStartPrev : BOOL := FALSE;
    opeModePrev : BOOL := FALSE;

    valveAStartRising : BOOL;
    valveBStartRising : BOOL;
    valveCStartRising : BOOL;
    valveDStartRising : BOOL;
    mixMotorStartRising : BOOL;
    autoStartRising : BOOL;
END_VAR

valveAStartRising := valveAStart AND (NOT valveAStartPrev);
valveBStartRising := valveBStart AND (NOT valveBStartPrev);
valveCStartRising := valveCStart AND (NOT valveCStartPrev);
valveDStartRising := valveDStart AND (NOT valveDStartPrev);
mixMotorStartRising := mixMotorStart AND (NOT mixMotorStartPrev);
autoStartRising := autoStart AND (NOT autoStartPrev);

IF NOT estop THEN
    valveARunCmd := FALSE;
    valveBRunCmd := FALSE;
    valveCRunCmd := FALSE;
    valveDRunCmd := FALSE;
    mixMotorRunCmd := FALSE;
    autoStep := 0;

ELSIF NOT opeMode THEN
    autoStep := 0;

    IF NOT opeModePrev THEN
        valveARunCmd := FALSE;
        valveBRunCmd := FALSE;
        valveCRunCmd := FALSE;
        valveDRunCmd := FALSE;
        mixMotorRunCmd := FALSE;
    ELSE
        IF valveAStartRising THEN
            valveARunCmd := NOT valveARunCmd;
        END_IF;

        IF valveBStartRising THEN
            valveBRunCmd := NOT valveBRunCmd;
        END_IF;

        IF valveCStartRising THEN
            valveCRunCmd := NOT valveCRunCmd;
        END_IF;

        IF valveDStartRising THEN
            valveDRunCmd := NOT valveDRunCmd;
        END_IF;

        IF mixMotorStartRising THEN
            mixMotorRunCmd := NOT mixMotorRunCmd;
        END_IF;
    END_IF;

ELSE
    IF NOT opeModePrev THEN
        autoStep := 0;
    END_IF;

    valveARunCmd := FALSE;
    valveBRunCmd := FALSE;
    valveCRunCmd := FALSE;
    valveDRunCmd := FALSE;
    mixMotorRunCmd := FALSE;

    IF autoStartRising THEN
        autoStep := 10;
        valveARunCmd := TRUE;

    ELSIF autoStep = 10 THEN
        IF levelSensor >= 50 THEN
            valveARunCmd := FALSE;
            valveBRunCmd := TRUE;
            autoStep := 20;
        ELSE
            valveARunCmd := TRUE;
        END_IF;

    ELSIF autoStep = 20 THEN
        IF levelSensor >= 80 THEN
            valveBRunCmd := FALSE;
            IF processMode THEN
                valveCRunCmd := TRUE;
                autoStep := 30;
            ELSE
                mixMotorRunCmd := TRUE;
                autoStep := 40;
            END_IF;
        ELSE
            valveBRunCmd := TRUE;
        END_IF;

    ELSIF autoStep = 30 THEN
        IF levelSensor >= 100 THEN
            valveCRunCmd := FALSE;
            mixMotorRunCmd := TRUE;
            autoStep := 40;
        ELSE
            valveCRunCmd := TRUE;
        END_IF;

    ELSIF autoStep = 40 THEN
        IF mixMotorComplete THEN
            mixMotorRunCmd := FALSE;
            valveDRunCmd := TRUE;
            autoStep := 50;
        ELSE
            mixMotorRunCmd := TRUE;
        END_IF;

    ELSIF autoStep = 50 THEN
        valveDRunCmd := TRUE;
    END_IF;
END_IF;

valveARun := valveARunCmd;
valveBRun := valveBRunCmd;
valveCRun := valveCRunCmd;
valveDRun := valveDRunCmd;
mixMotorRun := mixMotorRunCmd;

valveAStartPrev := valveAStart;
valveBStartPrev := valveBStart;
valveCStartPrev := valveCStart;
valveDStartPrev := valveDStart;
mixMotorStartPrev := mixMotorStart;
autoStartPrev := autoStart;
opeModePrev := opeMode;

END_FUNCTION_BLOCK