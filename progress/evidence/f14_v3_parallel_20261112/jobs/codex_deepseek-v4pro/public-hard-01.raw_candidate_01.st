FUNCTION_BLOCK MaterialProportioningControl
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
    ValveAStartPrev : BOOL;
    ValveBStartPrev : BOOL;
    ValveCStartPrev : BOOL;
    ValveDStartPrev : BOOL;
    MixMotorStartPrev : BOOL;
    AutoStartPrev : BOOL;
    ValveAEdge : BOOL;
    ValveBEdge : BOOL;
    ValveCEdge : BOOL;
    ValveDEdge : BOOL;
    MixMotorEdge : BOOL;
    AutoStartEdge : BOOL;
    ManualValveA : BOOL;
    ManualValveB : BOOL;
    ManualValveC : BOOL;
    ManualValveD : BOOL;
    ManualMixMotor : BOOL;
    AutoState : INT := 0;
END_VAR

ValveAEdge := valveAStart AND NOT ValveAStartPrev;
ValveAStartPrev := valveAStart;

ValveBEdge := valveBStart AND NOT ValveBStartPrev;
ValveBStartPrev := valveBStart;

ValveCEdge := valveCStart AND NOT ValveCStartPrev;
ValveCStartPrev := valveCStart;

ValveDEdge := valveDStart AND NOT ValveDStartPrev;
ValveDStartPrev := valveDStart;

MixMotorEdge := mixMotorStart AND NOT MixMotorStartPrev;
MixMotorStartPrev := mixMotorStart;

AutoStartEdge := autoStart AND NOT AutoStartPrev;
AutoStartPrev := autoStart;

IF NOT estop THEN
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;
ELSIF NOT opeMode THEN
    IF ValveAEdge THEN
        ManualValveA := NOT ManualValveA;
    END_IF;

    IF ValveBEdge THEN
        ManualValveB := NOT ManualValveB;
    END_IF;

    IF ValveCEdge THEN
        ManualValveC := NOT ManualValveC;
    END_IF;

    IF ValveDEdge THEN
        ManualValveD := NOT ManualValveD;
    END_IF;

    IF MixMotorEdge THEN
        ManualMixMotor := NOT ManualMixMotor;
    END_IF;

    valveARun := ManualValveA;
    valveBRun := ManualValveB;
    valveCRun := ManualValveC;
    valveDRun := ManualValveD;
    mixMotorRun := ManualMixMotor;
ELSE
    IF AutoStartEdge THEN
        AutoState := 10;
    END_IF;

    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;

    CASE AutoState OF
        0:
            valveDRun := FALSE;

        10:
            valveARun := TRUE;
            IF levelSensor >= 50 THEN
                AutoState := 20;
            END_IF;

        20:
            valveBRun := TRUE;
            IF levelSensor >= 80 THEN
                AutoState := 30;
            END_IF;

        30:
            IF processMode THEN
                AutoState := 35;
            ELSE
                AutoState := 40;
            END_IF;

        35:
            valveCRun := TRUE;
            IF levelSensor >= 100 THEN
                AutoState := 40;
            END_IF;

        40:
            mixMotorRun := TRUE;
            IF mixMotorComplete THEN
                AutoState := 50;
            END_IF;

        50:
            valveDRun := TRUE;
            AutoState := 60;

        60:
            valveDRun := TRUE;
    END_CASE;
END_IF;
END_FUNCTION_BLOCK