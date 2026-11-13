(* CONTRACT_RULES [] *)

(* ENGINEERING_CONTRACT
   - ESTOP: ESTOP=FALSE forces every output OFF in this scan; manual and auto commands are inhibited.
   - Manual runs: only while OpeMode=FALSE and ESTOP=TRUE; each start button rising edge toggles its retained output latch.
   - Auto sequence: AUTOSTART rising edge while OpeMode=TRUE enters FILL_A; output valves follow the sequence below.
   - Valve A: ON in FILL_A; Level>=50 closes A and opens B (PUB012).
   - Valve B: ON in FILL_B; Level>=80 closes B (PUB012/PUB013).
   - ProcessMode=FALSE: at Level>=80 mixer starts; MixMotorComplete latches completion, then mixer off and Valve D ON, sequence done (PUB014).
   - ProcessMode=TRUE: at Level>=80 Valve C opens; Level>=100 closes C and starts mixer; completion opens D (PUB014).
   - Mix complete is latched until the next AUTOSTART; Valve D remains ON in DONE because no stop/reset is stated.
   - Thresholds are inclusive >=; Level is INT cm; PROCESSMODE is read live at the 80 cm transition.
*)

TYPE E_MaterialProportioningState :
(
    MP_IDLE,
    MP_FILL_A,
    MP_FILL_B,
    MP_MIX_SIMPLE,
    MP_FILL_C,
    MP_MIX_C,
    MP_DONE
) := MP_IDLE;
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
    tmp_trigValveA : R_TRIG;
    tmp_trigValveB : R_TRIG;
    tmp_trigValveC : R_TRIG;
    tmp_trigValveD : R_TRIG;
    tmp_trigMixMotor : R_TRIG;
    tmp_trigAutoStart : R_TRIG;

    manualValveARun : BOOL := FALSE;
    manualValveBRun : BOOL := FALSE;
    manualValveCRun : BOOL := FALSE;
    manualValveDRun : BOOL := FALSE;
    manualMixMotorRun : BOOL := FALSE;

    state : E_MaterialProportioningState := MP_IDLE;
    mixCompleteLatched : BOOL := FALSE;
END_VAR

tmp_trigValveA(CLK := valveAStart);
tmp_trigValveB(CLK := valveBStart);
tmp_trigValveC(CLK := valveCStart);
tmp_trigValveD(CLK := valveDStart);
tmp_trigMixMotor(CLK := mixMotorStart);
tmp_trigAutoStart(CLK := autoStart);

IF NOT estop THEN
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;

ELSIF NOT opeMode THEN
    state := MP_IDLE;
    mixCompleteLatched := FALSE;

    IF tmp_trigValveA.Q THEN
        manualValveARun := NOT manualValveARun;
    END_IF;
    IF tmp_trigValveB.Q THEN
        manualValveBRun := NOT manualValveBRun;
    END_IF;
    IF tmp_trigValveC.Q THEN
        manualValveCRun := NOT manualValveCRun;
    END_IF;
    IF tmp_trigValveD.Q THEN
        manualValveDRun := NOT manualValveDRun;
    END_IF;
    IF tmp_trigMixMotor.Q THEN
        manualMixMotorRun := NOT manualMixMotorRun;
    END_IF;

    valveARun := manualValveARun;
    valveBRun := manualValveBRun;
    valveCRun := manualValveCRun;
    valveDRun := manualValveDRun;
    mixMotorRun := manualMixMotorRun;

ELSE
    IF tmp_trigAutoStart.Q THEN
        state := MP_FILL_A;
        mixCompleteLatched := FALSE;
    END_IF;

    CASE state OF
        MP_IDLE:
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;

        MP_FILL_A:
            valveARun := TRUE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;

            IF levelSensor >= 50 THEN
                valveARun := FALSE;
                valveBRun := TRUE;
                state := MP_FILL_B;
            END_IF;

        MP_FILL_B:
            valveARun := FALSE;
            valveBRun := TRUE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;

            IF levelSensor >= 80 THEN
                valveBRun := FALSE;
                IF NOT processMode THEN
                    mixMotorRun := TRUE;
                    mixCompleteLatched := FALSE;
                    state := MP_MIX_SIMPLE;
                ELSE
                    valveCRun := TRUE;
                    state := MP_FILL_C;
                END_IF;
            END_IF;

        MP_FILL_C:
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := TRUE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;

            IF levelSensor >= 100 THEN
                valveCRun := FALSE;
                mixMotorRun := TRUE;
                mixCompleteLatched := FALSE;
                state := MP_MIX_C;
            END_IF;

        MP_MIX_SIMPLE:
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := TRUE;

            IF mixMotorComplete THEN
                mixCompleteLatched := TRUE;
            END_IF;

            IF mixCompleteLatched THEN
                mixMotorRun := FALSE;
                valveDRun := TRUE;
                state := MP_DONE;
            END_IF;

        MP_MIX_C:
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := TRUE;

            IF mixMotorComplete THEN
                mixCompleteLatched := TRUE;
            END_IF;

            IF mixCompleteLatched THEN
                mixMotorRun := FALSE;
                valveDRun := TRUE;
                state := MP_DONE;
            END_IF;

        MP_DONE:
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := TRUE;
            mixMotorRun := FALSE;
    END_CASE;
END_IF;
END_FUNCTION_BLOCK