FUNCTION_BLOCK MaterialProportioningControl
VAR_INPUT
    estop            : BOOL;  (* FALSE = emergency stop active *)
    opeMode          : BOOL;  (* FALSE = manual, TRUE = automatic *)
    valveAStart      : BOOL;
    valveBStart      : BOOL;
    valveCStart      : BOOL;
    valveDStart      : BOOL;
    mixMotorStart    : BOOL;
    autoStart        : BOOL;
    processMode      : BOOL;  (* FALSE = no C, TRUE = use C until 100 cm *)
    levelSensor      : INT;   (* cm *)
    mixMotorComplete : BOOL;
END_VAR

VAR_OUTPUT
    valveARun   : BOOL;
    valveBRun   : BOOL;
    valveCRun   : BOOL;
    valveDRun   : BOOL;
    mixMotorRun : BOOL;
END_VAR

VAR
    valveAStart_RE      : BOOL;
    valveBStart_RE      : BOOL;
    valveCStart_RE      : BOOL;
    valveDStart_RE      : BOOL;
    mixMotorStart_RE    : BOOL;
    autoStart_RE        : BOOL;
    mixMotorComplete_RE : BOOL;
    modeChanged         : BOOL;

    valveAStart_prev      : BOOL;
    valveBStart_prev      : BOOL;
    valveCStart_prev      : BOOL;
    valveDStart_prev      : BOOL;
    mixMotorStart_prev    : BOOL;
    autoStart_prev        : BOOL;
    mixMotorComplete_prev : BOOL;
    opeMode_prev          : BOOL;

    manualValveA   : BOOL;
    manualValveB   : BOOL;
    manualValveC   : BOOL;
    manualValveD   : BOOL;
    manualMixMotor : BOOL;

    (* 0  = idle *)
    (* 10 = filling through valve A *)
    (* 20 = filling through valve B *)
    (* 30 = filling through valve C *)
    (* 40 = mixing *)
    (* 50 = discharging through valve D *)
    autoState : INT := 0;
END_VAR

(* Detect rising edges *)
valveAStart_RE      := valveAStart AND NOT valveAStart_prev;
valveBStart_RE      := valveBStart AND NOT valveBStart_prev;
valveCStart_RE      := valveCStart AND NOT valveCStart_prev;
valveDStart_RE      := valveDStart AND NOT valveDStart_prev;
mixMotorStart_RE    := mixMotorStart AND NOT mixMotorStart_prev;
autoStart_RE        := autoStart AND NOT autoStart_prev;
mixMotorComplete_RE := mixMotorComplete AND NOT mixMotorComplete_prev;
modeChanged         := opeMode <> opeMode_prev;

IF NOT estop THEN
    (* Emergency stop: stop everything and reset control states *)
    valveARun   := FALSE;
    valveBRun   := FALSE;
    valveCRun   := FALSE;
    valveDRun   := FALSE;
    mixMotorRun := FALSE;

    autoState      := 0;
    manualValveA   := FALSE;
    manualValveB   := FALSE;
    manualValveC   := FALSE;
    manualValveD   := FALSE;
    manualMixMotor := FALSE;

ELSIF modeChanged THEN
    (* Mode change: stop equipment and clear both control states *)
    valveARun   := FALSE;
    valveBRun   := FALSE;
    valveCRun   := FALSE;
    valveDRun   := FALSE;
    mixMotorRun := FALSE;

    autoState      := 0;
    manualValveA   := FALSE;
    manualValveB   := FALSE;
    manualValveC   := FALSE;
    manualValveD   := FALSE;
    manualMixMotor := FALSE;

ELSIF opeMode THEN
    (* Automatic mode *)

    IF autoStart_RE AND ((autoState = 0) OR (autoState = 50)) THEN
        autoState := 10;
    END_IF;

    CASE autoState OF
        10: (* Valve A is open; fill to 50 cm *)
            IF levelSensor >= 50 THEN
                autoState := 20;
            END_IF;

        20: (* Valve A closed, valve B open; fill to 80 cm *)
            IF levelSensor >= 80 THEN
                IF processMode THEN
                    autoState := 30;
                ELSE
                    autoState := 40;
                END_IF;
            END_IF;

        30: (* Valve C open; fill to 100 cm *)
            IF levelSensor >= 100 THEN
                autoState := 40;
            END_IF;

        40: (* Mixing motor running *)
            IF mixMotorComplete_RE THEN
                autoState := 50;
            END_IF;

        50: (* Valve D open; automatic process finished *)
            ;
    END_CASE;

    valveARun   := autoState = 10;
    valveBRun   := autoState = 20;
    valveCRun   := autoState = 30;
    valveDRun   := autoState = 50;
    mixMotorRun := autoState = 40;

ELSE
    (* Manual mode: each rising edge toggles the corresponding device *)
    valveARun   := manualValveA;
    valveBRun   := manualValveB;
    valveCRun   := manualValveC;
    valveDRun   := manualValveD;
    mixMotorRun := manualMixMotor;

    IF valveAStart_RE THEN
        manualValveA := NOT manualValveA;
    END_IF;

    IF valveBStart_RE THEN
        manualValveB := NOT manualValveB;
    END_IF;

    IF valveCStart_RE THEN
        manualValveC := NOT manualValveC;
    END_IF;

    IF valveDStart_RE THEN
        manualValveD := NOT manualValveD;
    END_IF;

    IF mixMotorStart_RE THEN
        manualMixMotor := NOT manualMixMotor;
    END_IF;
END_IF;

(* Store current input values for the next rising-edge detection *)
valveAStart_prev      := valveAStart;
valveBStart_prev      := valveBStart;
valveCStart_prev      := valveCStart;
valveDStart_prev      := valveDStart;
mixMotorStart_prev    := mixMotorStart;
autoStart_prev        := autoStart;
mixMotorComplete_prev := mixMotorComplete;
opeMode_prev          := opeMode;