(* ENGINEERING_CONTRACT *)
(*
  PUB001: Emergency stop (estop=FALSE) immediately de-energizes all outputs (valveARun, valveBRun, valveCRun, valveDRun, mixMotorRun).
  PUB002: opeMode=FALSE selects Manual Mode; opeMode=TRUE selects Automatic Mode.
  PUB003: Manual Mode - rising edge on valveAStart toggles valveARun; similarly B/C/D and mixMotorStart each toggle their respective outputs.
  PUB004: Automatic Mode - rising edge on autoStart initiates sequence; valve A opens first.
  PUB005: Level >= 50 cm triggers close valve A + open valve B transition.
  PUB006: Level >= 80 cm triggers close valve B; processMode=FALSE skips valve C; processMode=TRUE proceeds to valve C fill.
  PUB007: processMode=TRUE: valve C opens at level>=80; level>=100 closes valve C.
  PUB008: After level>=80 (or level>=100 for processMode=TRUE), mixing motor starts on mixMotorComplete signal.
  PUB009: mixMotorComplete=TRUE stops mixing motor, opens valve D, and terminates the automatic sequence.
  PUB010: All outputs retain state across scans except when explicitly changed by state transitions or estop.
  PUB011: Rising-edge detection uses R_TRIG on momentary inputs; manual toggles are stateful across scans.
  PUB012: Level sensor thresholds are strict >= comparisons at integer resolution (cm).
  PUB013: No unstated resets, interlocks, or edge triggers beyond R_TRIG on start inputs.
  PUB014: Same-scan priority: output assignments before RETURN; state changes apply to subsequent scan.
  PUB015: Valve/motor stop on estop or mode change takes precedence over automatic sequence state.
*)
(* CONTRACT_RULES [] *)

TYPE AutoState :
(
    AUTO_IDLE      := 0,
    AUTO_FILL_A    := 1,
    AUTO_FILL_B    := 2,
    AUTO_FILL_C    := 3,
    AUTO_MIXING    := 4,
    AUTO_DRAINING  := 5
);
END_TYPE;

FUNCTION_BLOCK MaterialProportioning
VAR_INPUT
    estop           : BOOL;
    opeMode         : BOOL;
    valveAStart     : BOOL;
    valveBStart     : BOOL;
    valveCStart     : BOOL;
    valveDStart     : BOOL;
    mixMotorStart   : BOOL;
    autoStart       : BOOL;
    processMode     : BOOL;
    levelSensor     : INT;
    mixMotorComplete: BOOL;
END_VAR
VAR_OUTPUT
    valveARun       : BOOL;
    valveBRun       : BOOL;
    valveCRun       : BOOL;
    valveDRun       : BOOL;
    mixMotorRun     : BOOL;
END_VAR
VAR
    tmp_autoStartTrig    : R_TRIG;
    tmp_valveAStartTrig  : R_TRIG;
    tmp_valveBStartTrig  : R_TRIG;
    tmp_valveCStartTrig  : R_TRIG;
    tmp_valveDStartTrig  : R_TRIG;
    tmp_mixMotorStartTrig: R_TRIG;
    tmp_autoState        : AutoState := AUTO_IDLE;
    tmp_manualValveA     : BOOL;
    tmp_manualValveB     : BOOL;
    tmp_manualValveC     : BOOL;
    tmp_manualValveD     : BOOL;
    tmp_manualMixMotor   : BOOL;
END_VAR

(* Rising edge detection *)
tmp_autoStartTrig(CLK := autoStart);
tmp_valveAStartTrig(CLK := valveAStart);
tmp_valveBStartTrig(CLK := valveBStart);
tmp_valveCStartTrig(CLK := valveCStart);
tmp_valveDStartTrig(CLK := valveDStart);
tmp_mixMotorStartTrig(CLK := mixMotorStart);

(* Emergency stop: all outputs OFF immediately *)
IF NOT estop THEN
    valveARun  := FALSE;
    valveBRun  := FALSE;
    valveCRun  := FALSE;
    valveDRun  := FALSE;
    mixMotorRun := FALSE;
    tmp_autoState := AUTO_IDLE;
    tmp_manualValveA := FALSE;
    tmp_manualValveB := FALSE;
    tmp_manualValveC := FALSE;
    tmp_manualValveD := FALSE;
    tmp_manualMixMotor := FALSE;
    RETURN;
END_IF;

(* Mode selection *)
IF NOT opeMode THEN
    (* Manual Mode *)
    valveARun  := tmp_manualValveA;
    valveBRun  := tmp_manualValveB;
    valveCRun  := tmp_manualValveC;
    valveDRun  := tmp_manualValveD;
    mixMotorRun := tmp_manualMixMotor;
    tmp_autoState := AUTO_IDLE;

    IF tmp_valveAStartTrig.Q THEN
        tmp_manualValveA := NOT tmp_manualValveA;
    END_IF;
    IF tmp_valveBStartTrig.Q THEN
        tmp_manualValveB := NOT tmp_manualValveB;
    END_IF;
    IF tmp_valveCStartTrig.Q THEN
        tmp_manualValveC := NOT tmp_manualValveC;
    END_IF;
    IF tmp_valveDStartTrig.Q THEN
        tmp_manualValveD := NOT tmp_manualValveD;
    END_IF;
    IF tmp_mixMotorStartTrig.Q THEN
        tmp_manualMixMotor := NOT tmp_manualMixMotor;
    END_IF;
ELSE
    (* Automatic Mode *)
    tmp_manualValveA := FALSE;
    tmp_manualValveB := FALSE;
    tmp_manualValveC := FALSE;
    tmp_manualValveD := FALSE;
    tmp_manualMixMotor := FALSE;

    CASE TO_INT(tmp_autoState) OF
        0: (* AUTO_IDLE *)
            valveARun  := FALSE;
            valveBRun  := FALSE;
            valveCRun  := FALSE;
            valveDRun  := FALSE;
            mixMotorRun := FALSE;
            IF tmp_autoStartTrig.Q THEN
                tmp_autoState := AUTO_FILL_A;
            END_IF;

        1: (* AUTO_FILL_A *)
            valveARun := TRUE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
            IF levelSensor >= 50 THEN
                valveARun := FALSE;
                valveBRun := TRUE;
                tmp_autoState := AUTO_FILL_B;
            END_IF;

        2: (* AUTO_FILL_B *)
            valveARun := FALSE;
            valveBRun := TRUE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
            IF levelSensor >= 80 THEN
                valveBRun := FALSE;
                IF NOT processMode THEN
                    tmp_autoState := AUTO_MIXING;
                ELSE
                    valveCRun := TRUE;
                    tmp_autoState := AUTO_FILL_C;
                END_IF;
            END_IF;

        3: (* AUTO_FILL_C *)
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := TRUE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;
            IF levelSensor >= 100 THEN
                valveCRun := FALSE;
                tmp_autoState := AUTO_MIXING;
            END_IF;

        4: (* AUTO_MIXING *)
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := TRUE;
            IF mixMotorComplete THEN
                mixMotorRun := FALSE;
                valveDRun := TRUE;
                tmp_autoState := AUTO_DRAINING;
            END_IF;

        5: (* AUTO_DRAINING *)
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := TRUE;
            mixMotorRun := FALSE;
            tmp_autoState := AUTO_IDLE;

    END_CASE;
END_IF;

END_FUNCTION_BLOCK