TYPE AutoState : (ST_IDLE, ST_OPEN_A, ST_OPEN_B, ST_OPEN_C, ST_MIXING);
END_TYPE

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
    trigA : R_TRIG;
    trigB : R_TRIG;
    trigC : R_TRIG;
    trigD : R_TRIG;
    trigMix : R_TRIG;
    trigAuto : R_TRIG;

    manualA : BOOL := FALSE;
    manualB : BOOL := FALSE;
    manualC : BOOL := FALSE;
    manualD : BOOL := FALSE;
    manualMixer : BOOL := FALSE;

    autoActive : BOOL := FALSE;
    autoState : AutoState := ST_IDLE;
    finalDCommand : BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT
Manual outputs: set/toggled on rising edge of each start input while opeMode=FALSE.
Manual outputs retain until next rising edge of same input or estop=FALSE.
Automatic sequence outputs: activated by autoStart rising edge while opeMode=TRUE and not already active.
State thresholds: levelSensor >= 50 (A->B), >= 80 (B->C or B->mix), >= 100 (C->mix).
processMode is evaluated at the 80 cm transition only.
Mixer stops and valve D opens on mixMotorComplete=TRUE while mixing.
valveDRun remains held by finalDCommand after automatic process ends until next autoStart or estop.
Priority: estop=FALSE forces all outputs FALSE and resets all manual/automatic state.
Same-scan: autoStart sets ST_OPEN_A and outputs without immediate threshold transition; other transitions are one state per scan.
Units: levelSensor cm. PUB001-PUB015.
*)

(* CONTRACT_RULES [] *)

// Rising-edge detection is updated every scan, including during emergency stop.
trigA(CLK := valveAStart);
trigB(CLK := valveBStart);
trigC(CLK := valveCStart);
trigD(CLK := valveDStart);
trigMix(CLK := mixMotorStart);
trigAuto(CLK := autoStart);

IF NOT estop THEN
    // Emergency stop: stop everything immediately and reset all retained state.
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;

    manualA := FALSE;
    manualB := FALSE;
    manualC := FALSE;
    manualD := FALSE;
    manualMixer := FALSE;

    autoActive := FALSE;
    autoState := ST_IDLE;
    finalDCommand := FALSE;

    RETURN;
END_IF

IF NOT opeMode THEN
    // Manual operation mode.
    IF trigA.Q THEN
        manualA := NOT manualA;
    END_IF;
    IF trigB.Q THEN
        manualB := NOT manualB;
    END_IF;
    IF trigC.Q THEN
        manualC := NOT manualC;
    END_IF;
    IF trigD.Q THEN
        manualD := NOT manualD;
    END_IF;
    IF trigMix.Q THEN
        manualMixer := NOT manualMixer;
    END_IF;

    valveARun := manualA;
    valveBRun := manualB;
    valveCRun := manualC;
    valveDRun := manualD;
    mixMotorRun := manualMixer;

ELSE
    // Automatic operation mode.
    IF trigAuto.Q AND NOT autoActive THEN
        // Start new automatic process: open valve A first.
        autoActive := TRUE;
        autoState := ST_OPEN_A;
        finalDCommand := FALSE;

        valveARun := TRUE;
        valveBRun := FALSE;
        valveCRun := FALSE;
        valveDRun := FALSE;
        mixMotorRun := FALSE;
    ELSE
        CASE autoState OF
            ST_IDLE:
                valveARun := FALSE;
                valveBRun := FALSE;
                valveCRun := FALSE;
                valveDRun := finalDCommand;
                mixMotorRun := FALSE;

            ST_OPEN_A:
                valveARun := TRUE;
                valveBRun := FALSE;
                valveCRun := FALSE;
                valveDRun := FALSE;
                mixMotorRun := FALSE;

                IF levelSensor >= 50 THEN
                    autoState := ST_OPEN_B;
                    valveARun := FALSE;
                    valveBRun := TRUE;
                END_IF;

            ST_OPEN_B:
                valveARun := FALSE;
                valveBRun := TRUE;
                valveCRun := FALSE;
                valveDRun := FALSE;
                mixMotorRun := FALSE;

                IF levelSensor >= 80 THEN
                    IF NOT processMode THEN
                        // processMode = FALSE: close B, start mixer.
                        autoState := ST_MIXING;
                        valveBRun := FALSE;
                        mixMotorRun := TRUE;
                    ELSE
                        // processMode = TRUE: close B, open C.
                        autoState := ST_OPEN_C;
                        valveBRun := FALSE;
                        valveCRun := TRUE;
                    END_IF;
                END_IF;

            ST_OPEN_C:
                valveARun := FALSE;
                valveBRun := FALSE;
                valveCRun := TRUE;
                valveDRun := FALSE;
                mixMotorRun := FALSE;

                IF levelSensor >= 100 THEN
                    autoState := ST_MIXING;
                    valveCRun := FALSE;
                    mixMotorRun := TRUE;
                END_IF;

            ST_MIXING:
                valveARun := FALSE;
                valveBRun := FALSE;
                valveCRun := FALSE;
                valveDRun := FALSE;
                mixMotorRun := TRUE;

                IF mixMotorComplete THEN
                    mixMotorRun := FALSE;
                    valveDRun := TRUE;
                    finalDCommand := TRUE;
                    autoActive := FALSE;
                    autoState := ST_IDLE;
                END_IF;
        END_CASE;
    END_IF;
END_IF;