FUNCTION_BLOCK MaterialProportioningControl
VAR CONSTANT
    STATE_IDLE : INT := 0;
    STATE_VALVE_A : INT := 1;
    STATE_VALVE_B : INT := 2;
    STATE_VALVE_C : INT := 3;
    STATE_MIXING : INT := 4;
    STATE_DONE : INT := 5;
END_VAR
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
    manValveA : BOOL := FALSE;
    manValveB : BOOL := FALSE;
    manValveC : BOOL := FALSE;
    manValveD : BOOL := FALSE;
    manMixMotor : BOOL := FALSE;
    prevAutoStart : BOOL := FALSE;
    prevValveAStart : BOOL := FALSE;
    prevValveBStart : BOOL := FALSE;
    prevValveCStart : BOOL := FALSE;
    prevValveDStart : BOOL := FALSE;
    prevMixMotorStart : BOOL := FALSE;
    autoState : INT := STATE_IDLE;
END_VAR

IF NOT estop THEN
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;
    manValveA := FALSE;
    manValveB := FALSE;
    manValveC := FALSE;
    manValveD := FALSE;
    manMixMotor := FALSE;
    autoState := STATE_IDLE;
ELSE
    IF NOT opeMode THEN
        (* Manual mode *)
        IF valveAStart AND NOT prevValveAStart THEN
            manValveA := NOT manValveA;
        END_IF;
        IF valveBStart AND NOT prevValveBStart THEN
            manValveB := NOT manValveB;
        END_IF;
        IF valveCStart AND NOT prevValveCStart THEN
            manValveC := NOT manValveC;
        END_IF;
        IF valveDStart AND NOT prevValveDStart THEN
            manValveD := NOT manValveD;
        END_IF;
        IF mixMotorStart AND NOT prevMixMotorStart THEN
            manMixMotor := NOT manMixMotor;
        END_IF;
        valveARun := manValveA;
        valveBRun := manValveB;
        valveCRun := manValveC;
        valveDRun := manValveD;
        mixMotorRun := manMixMotor;
        autoState := STATE_IDLE;
    ELSE
        (* Automatic mode *)
        IF autoStart AND NOT prevAutoStart THEN
            autoState := STATE_VALVE_A;
        END_IF;

        (* State transition logic *)
        CASE autoState OF
            STATE_IDLE:
                (* No transition *)
            STATE_VALVE_A:
                IF levelSensor >= 50 THEN
                    autoState := STATE_VALVE_B;
                END_IF;
            STATE_VALVE_B:
                IF levelSensor >= 80 THEN
                    IF processMode THEN
                        autoState := STATE_VALVE_C;
                    ELSE
                        autoState := STATE_MIXING;
                    END_IF;
                END_IF;
            STATE_VALVE_C:
                IF levelSensor >= 100 THEN
                    autoState := STATE_MIXING;
                END_IF;
            STATE_MIXING:
                IF mixMotorComplete THEN
                    autoState := STATE_DONE;
                END_IF;
            STATE_DONE:
                (* Hold final state until next start *)
        END_CASE;

        (* Output based on updated state *)
        CASE autoState OF
            STATE_IDLE:
                valveARun := FALSE;
                valveBRun := FALSE;
                valveCRun := FALSE;
                valveDRun := FALSE;
                mixMotorRun := FALSE;
            STATE_VALVE_A:
                valveARun := TRUE;
                valveBRun := FALSE;
                valveCRun := FALSE;
                valveDRun := FALSE;
                mixMotorRun := FALSE;
            STATE_VALVE_B:
                valveARun := FALSE;
                valveBRun := TRUE;
                valveCRun := FALSE;
                valveDRun := FALSE;
                mixMotorRun := FALSE;
            STATE_VALVE_C:
                valveARun := FALSE;
                valveBRun := FALSE;
                valveCRun := TRUE;
                valveDRun := FALSE;
                mixMotorRun := FALSE;
            STATE_MIXING:
                valveARun := FALSE;
                valveBRun := FALSE;
                valveCRun := FALSE;
                valveDRun := FALSE;
                mixMotorRun := TRUE;
            STATE_DONE:
                valveARun := FALSE;
                valveBRun := FALSE;
                valveCRun := FALSE;
                valveDRun := TRUE;
                mixMotorRun := FALSE;
        END_CASE;
    END_IF;
END_IF;

(* Update previous input states *)
prevAutoStart := autoStart;
prevValveAStart := valveAStart;
prevValveBStart := valveBStart;
prevValveCStart := valveCStart;
prevValveDStart := valveDStart;
prevMixMotorStart := mixMotorStart;

END_FUNCTION_BLOCK