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
    AutoActive : BOOL;
    AutoComplete : BOOL;
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
        AutoActive := TRUE;
        AutoComplete := FALSE;
    END_IF;

    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;

    IF AutoActive THEN
        IF AutoComplete THEN
            valveDRun := TRUE;
        ELSIF levelSensor < 50 THEN
            valveARun := TRUE;
        ELSIF levelSensor < 80 THEN
            valveBRun := TRUE;
        ELSIF processMode AND (levelSensor < 100) THEN
            valveCRun := TRUE;
        ELSE
            IF mixMotorComplete THEN
                AutoComplete := TRUE;
                valveDRun := TRUE;
            ELSE
                mixMotorRun := TRUE;
            END_IF;
        END_IF;
    END_IF;
END_IF;
END_FUNCTION_BLOCK