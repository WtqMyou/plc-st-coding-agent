PROGRAM MaterialProportioningControl
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
    (* Previous states for edge detection *)
    prevValveAStart : BOOL;
    prevValveBStart : BOOL;
    prevValveCStart : BOOL;
    prevValveDStart : BOOL;
    prevMixMotorStart : BOOL;
    prevAutoStart : BOOL;
    prevMixMotorComplete : BOOL;

    (* Rising edge flags *)
    valveAStartRise : BOOL;
    valveBStartRise : BOOL;
    valveCStartRise : BOOL;
    valveDStartRise : BOOL;
    mixMotorStartRise : BOOL;
    autoStartRise : BOOL;
    mixMotorCompleteRise : BOOL;

    (* Automatic process state *)
    autoState : INT := 0;
    (* 0  - idle
       10 - filling A
       20 - filling B
       30 - filling C (only when processMode = TRUE)
       40 - mixing
       50 - discharging / process complete *)
END_VAR

(* --- Edge detection --- *)
valveAStartRise := valveAStart AND NOT prevValveAStart;
valveBStartRise := valveBStart AND NOT prevValveBStart;
valveCStartRise := valveCStart AND NOT prevValveCStart;
valveDStartRise := valveDStart AND NOT prevValveDStart;
mixMotorStartRise := mixMotorStart AND NOT prevMixMotorStart;
autoStartRise := autoStart AND NOT prevAutoStart;
mixMotorCompleteRise := mixMotorComplete AND NOT prevMixMotorComplete;

(* --- Emergency stop: stop everything immediately --- *)
IF NOT estop THEN
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;
    autoState := 0;

(* --- Manual mode --- *)
ELSIF NOT opeMode THEN
    autoState := 0;

    IF valveAStartRise THEN
        valveARun := NOT valveARun;
    END_IF;

    IF valveBStartRise THEN
        valveBRun := NOT valveBRun;
    END_IF;

    IF valveCStartRise THEN
        valveCRun := NOT valveCRun;
    END_IF;

    IF valveDStartRise THEN
        valveDRun := NOT valveDRun;
    END_IF;

    IF mixMotorStartRise THEN
        mixMotorRun := NOT mixMotorRun;
    END_IF;

(* --- Automatic mode --- *)
ELSE
    (* Default all outputs off; the active state will turn on what is needed *)
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;

    (* Start a new automatic process from idle or done state *)
    IF autoStartRise AND (autoState = 0 OR autoState = 50) THEN
        autoState := 10;
    END_IF;

    CASE autoState OF
        10: (* Filling with material A *)
            valveARun := TRUE;
            IF levelSensor >= 50 THEN
                autoState := 20;
            END_IF;

        20: (* Filling with material B *)
            valveBRun := TRUE;
            IF levelSensor >= 80 THEN
                IF processMode THEN
                    autoState := 30;
                ELSE
                    autoState := 40;
                END_IF;
            END_IF;

        30: (* Filling with material C, only processMode = TRUE *)
            valveCRun := TRUE;
            IF levelSensor >= 100 THEN
                autoState := 40;
            END_IF;

        40: (* Mixing *)
            mixMotorRun := TRUE;
            IF mixMotorCompleteRise THEN
                mixMotorRun := FALSE;
                autoState := 50;
            END_IF;

        50: (* Discharge through valve D, process complete *)
            valveDRun := TRUE;
    END_CASE;
END_IF;

(* --- Store current states for next scan --- *)
prevValveAStart := valveAStart;
prevValveBStart := valveBStart;
prevValveCStart := valveCStart;
prevValveDStart := valveDStart;
prevMixMotorStart := mixMotorStart;
prevAutoStart := autoStart;
prevMixMotorComplete := mixMotorComplete;

END_PROGRAM