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
    valveAStartPrev : BOOL;
    valveBStartPrev : BOOL;
    valveCStartPrev : BOOL;
    valveDStartPrev : BOOL;
    mixMotorStartPrev : BOOL;
    autoStartPrev : BOOL;
    mixMotorCompletePrev : BOOL;
    opeModePrev : BOOL;

    valveAStartR : BOOL;
    valveBStartR : BOOL;
    valveCStartR : BOOL;
    valveDStartR : BOOL;
    mixMotorStartR : BOOL;
    autoStartR : BOOL;
    mixMotorCompleteR : BOOL;
    modeChanged : BOOL;

    manualValveA : BOOL;
    manualValveB : BOOL;
    manualValveC : BOOL;
    manualValveD : BOOL;
    manualMixMotor : BOOL;

    state : INT;
    nextState : INT;
END_VAR

valveAStartR := valveAStart AND NOT valveAStartPrev;
valveBStartR := valveBStart AND NOT valveBStartPrev;
valveCStartR := valveCStart AND NOT valveCStartPrev;
valveDStartR := valveDStart AND NOT valveDStartPrev;
mixMotorStartR := mixMotorStart AND NOT mixMotorStartPrev;
autoStartR := autoStart AND NOT autoStartPrev;
mixMotorCompleteR := mixMotorComplete AND NOT mixMotorCompletePrev;
modeChanged := opeMode <> opeModePrev;

IF NOT estop THEN
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;

    manualValveA := FALSE;
    manualValveB := FALSE;
    manualValveC := FALSE;
    manualValveD := FALSE;
    manualMixMotor := FALSE;
    state := 0;
    nextState := 0;

ELSIF modeChanged THEN
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;

    manualValveA := FALSE;
    manualValveB := FALSE;
    manualValveC := FALSE;
    manualValveD := FALSE;
    manualMixMotor := FALSE;
    state := 0;
    nextState := 0;

ELSIF opeMode THEN
    nextState := state;

    CASE state OF
        0:
            IF autoStartR THEN
                nextState := 1;
            END_IF;

        1:
            IF levelSensor >= 50 THEN
                nextState := 2;
            END_IF;

        2:
            IF levelSensor >= 80 THEN
                IF processMode THEN
                    nextState := 3;
                ELSE
                    nextState := 4;
                END_IF;
            END_IF;

        3:
            IF levelSensor >= 100 THEN
                nextState := 4;
            END_IF;

        4:
            IF mixMotorCompleteR THEN
                nextState := 5;
            END_IF;

        5:
            IF autoStartR THEN
                nextState := 1;
            END_IF;

        ELSE
            nextState := 0;
    END_CASE;

    state := nextState;

    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;

    CASE state OF
        1:
            valveARun := TRUE;

        2:
            valveBRun := TRUE;

        3:
            valveCRun := TRUE;

        4:
            mixMotorRun := TRUE;

        5:
            valveDRun := TRUE;
    END_CASE;

ELSE
    IF valveAStartR THEN
        manualValveA := NOT manualValveA;
    END_IF;

    IF valveBStartR THEN
        manualValveB := NOT manualValveB;
    END_IF;

    IF valveCStartR THEN
        manualValveC := NOT manualValveC;
    END_IF;

    IF valveDStartR THEN
        manualValveD := NOT manualValveD;
    END_IF;

    IF mixMotorStartR THEN
        manualMixMotor := NOT manualMixMotor;
    END_IF;

    valveARun := manualValveA;
    valveBRun := manualValveB;
    valveCRun := manualValveC;
    valveDRun := manualValveD;
    mixMotorRun := manualMixMotor;
END_IF;

valveAStartPrev := valveAStart;
valveBStartPrev := valveBStart;
valveCStartPrev := valveCStart;
valveDStartPrev := valveDStart;
mixMotorStartPrev := mixMotorStart;
autoStartPrev := autoStart;
mixMotorCompletePrev := mixMotorComplete;
opeModePrev := opeMode;

END_FUNCTION_BLOCK