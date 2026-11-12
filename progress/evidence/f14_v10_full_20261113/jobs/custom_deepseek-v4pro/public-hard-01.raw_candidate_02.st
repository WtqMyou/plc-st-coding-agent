(* ENGINEERING_CONTRACT
   valveARun / valveBRun / valveCRun / valveDRun / mixMotorRun:
   - Activation: manual rising-edge toggle per PUB001; auto STATES OPEN_A/OPEN_B/WAIT_C/DONE/MIXING per PUB005-PUB010.
   - Retention: hold while selected mode/state condition remains; manual toggles hold until next edge, estop FALSE, or mode change.
   - Reset/deactivation: estop=FALSE forces all FALSE and resets manual/auto state; auto transitions close prior actuator; autoStart restart wins after transitions.
   - Same-scan priority: estop overrides all; manual outputs assigned only in manual; auto transitions selected on old state, then autoStart assignment wins.
   - levelSensor units cm, thresholds >=50, >=80, >=100; processMode sampled at 80 cm branch; mixMotorComplete edge accepted only while auto MIXING.
   - Unspecified: mode switch retains auto state; after estop clear, auto requires autoStart; manual requires button restart.
*)
(* CONTRACT_RULES [] *)

TYPE AUTO_STATE : (IDLE, OPEN_A, OPEN_B, WAIT_C, MIXING, DONE);
END_TYPE;

FUNCTION_BLOCK MaterialProportioningProcessControl
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
    manualValveA : BOOL := FALSE;
    manualValveB : BOOL := FALSE;
    manualValveC : BOOL := FALSE;
    manualValveD : BOOL := FALSE;
    manualMixMotor : BOOL := FALSE;

    autoState : AUTO_STATE := IDLE;

    rt_valveA : R_TRIG;
    rt_valveB : R_TRIG;
    rt_valveC : R_TRIG;
    rt_valveD : R_TRIG;
    rt_mixMotor : R_TRIG;
    rt_autoStart : R_TRIG;
    rt_mixComplete : R_TRIG;

    tmp_autoValveA : BOOL;
    tmp_autoValveB : BOOL;
    tmp_autoValveC : BOOL;
    tmp_autoValveD : BOOL;
    tmp_autoMixMotor : BOOL;
END_VAR

// Update rising-edge detectors
rt_valveA(CLK := valveAStart);
rt_valveB(CLK := valveBStart);
rt_valveC(CLK := valveCStart);
rt_valveD(CLK := valveDStart);
rt_mixMotor(CLK := mixMotorStart);
rt_autoStart(CLK := autoStart);
rt_mixComplete(CLK := mixMotorComplete);

// Emergency stop: reset all retained states while estop is FALSE
IF NOT estop THEN
    manualValveA := FALSE;
    manualValveB := FALSE;
    manualValveC := FALSE;
    manualValveD := FALSE;
    manualMixMotor := FALSE;
    autoState := IDLE;
END_IF;

// Manual toggle controls only in manual mode with no emergency stop
IF estop AND NOT opeMode THEN
    IF rt_valveA.Q THEN
        manualValveA := NOT manualValveA;
    END_IF;
    IF rt_valveB.Q THEN
        manualValveB := NOT manualValveB;
    END_IF;
    IF rt_valveC.Q THEN
        manualValveC := NOT manualValveC;
    END_IF;
    IF rt_valveD.Q THEN
        manualValveD := NOT manualValveD;
    END_IF;
    IF rt_mixMotor.Q THEN
        manualMixMotor := NOT manualMixMotor;
    END_IF;
END_IF;

// Automatic process state transitions
IF estop AND opeMode THEN
    CASE autoState OF
        OPEN_A:
            IF levelSensor >= 50 THEN
                autoState := OPEN_B;
            END_IF;

        OPEN_B:
            IF levelSensor >= 80 THEN
                IF NOT processMode THEN
                    autoState := MIXING;
                ELSE
                    autoState := WAIT_C;
                END_IF;
            END_IF;

        WAIT_C:
            IF levelSensor >= 100 THEN
                autoState := MIXING;
            END_IF;

        MIXING:
            IF rt_mixComplete.Q THEN
                autoState := DONE;
            END_IF;
    END_CASE;
END_IF;

// Auto start restarts the sequence and wins over same-scan state transitions
IF estop AND opeMode AND rt_autoStart.Q THEN
    autoState := OPEN_A;
END_IF;

// Compute temporary automatic outputs from current state
tmp_autoValveA := FALSE;
tmp_autoValveB := FALSE;
tmp_autoValveC := FALSE;
tmp_autoValveD := FALSE;
tmp_autoMixMotor := FALSE;

CASE autoState OF
    OPEN_A:
        tmp_autoValveA := TRUE;
    OPEN_B:
        tmp_autoValveB := TRUE;
    WAIT_C:
        tmp_autoValveC := TRUE;
    MIXING:
        tmp_autoMixMotor := TRUE;
    DONE:
        tmp_autoValveD := TRUE;
END_CASE;

// Final output assignment with emergency stop as highest priority
valveARun := FALSE;
valveBRun := FALSE;
valveCRun := FALSE;
valveDRun := FALSE;
mixMotorRun := FALSE;

IF estop AND NOT opeMode THEN
    valveARun := manualValveA;
    valveBRun := manualValveB;
    valveCRun := manualValveC;
    valveDRun := manualValveD;
    mixMotorRun := manualMixMotor;
ELSIF estop AND opeMode THEN
    valveARun := tmp_autoValveA;
    valveBRun := tmp_autoValveB;
    valveCRun := tmp_autoValveC;
    valveDRun := tmp_autoValveD;
    mixMotorRun := tmp_autoMixMotor;
END_IF;

END_FUNCTION_BLOCK