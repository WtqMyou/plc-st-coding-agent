(*
ENGINEERING_CONTRACT
Outputs/state group | activation | retention/hold | reset/deactivation | same-scan priority | units/bounds
estop: highest priority; active-low; all outputs false and internal states/latches reset (PUB001, PUB003).
Manual valve/motor: rising button toggles local latch; held between scans; reset by estop or mode change (PUB002, PUB004-PUB005).
AutoState: idle all off; fillA A on until level>=50; fillB B on until level>=80; processMode false->mix, true->fillC C on until level>=100; mix motor on until complete signal false->true while motor running; deliver D on and retained until autoStart/estop/mode change (PUB006-PUB015).
AutoStart rising restarts at fillA and suppresses threshold transition for first scan; transitions update state before output mapping this scan.
levelSensor INT cm; thresholds use >=.
mix completion uses armed condition requiring mixMotorComplete FALSE before TRUE while in mix state.
*)
(* CONTRACT_RULES [] *)
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
VAR CONSTANT
    AUTO_IDLE : INT := 0;
    AUTO_FILL_A : INT := 1;
    AUTO_FILL_B : INT := 2;
    AUTO_FILL_C : INT := 3;
    AUTO_MIX : INT := 4;
    AUTO_DELIVER : INT := 5;
END_VAR
VAR
    autoStartRtr : R_TRIG;
    valveAStartRtr : R_TRIG;
    valveBStartRtr : R_TRIG;
    valveCStartRtr : R_TRIG;
    valveDStartRtr : R_TRIG;
    mixMotorStartRtr : R_TRIG;

    local_prevOpeMode : BOOL := FALSE;
    local_init : BOOL := FALSE;

    local_manualA : BOOL := FALSE;
    local_manualB : BOOL := FALSE;
    local_manualC : BOOL := FALSE;
    local_manualD : BOOL := FALSE;
    local_manualMix : BOOL := FALSE;

    local_autoState : INT := AUTO_IDLE;
    local_firstAutoScan : BOOL := FALSE;
    local_mixArmed : BOOL := FALSE;

    local_autoStartEdge : BOOL;
    local_edgeA : BOOL;
    local_edgeB : BOOL;
    local_edgeC : BOOL;
    local_edgeD : BOOL;
    local_edgeMix : BOOL;
END_VAR

autoStartRtr(CLK := autoStart);
valveAStartRtr(CLK := valveAStart);
valveBStartRtr(CLK := valveBStart);
valveCStartRtr(CLK := valveCStart);
valveDStartRtr(CLK := valveDStart);
mixMotorStartRtr(CLK := mixMotorStart);

local_autoStartEdge := autoStartRtr.Q AND opeMode AND estop;
local_edgeA := valveAStartRtr.Q AND NOT opeMode AND estop;
local_edgeB := valveBStartRtr.Q AND NOT opeMode AND estop;
local_edgeC := valveCStartRtr.Q AND NOT opeMode AND estop;
local_edgeD := valveDStartRtr.Q AND NOT opeMode AND estop;
local_edgeMix := mixMotorStartRtr.Q AND NOT opeMode AND estop;

IF NOT local_init THEN
    local_prevOpeMode := opeMode;
    local_init := TRUE;
ELSIF local_prevOpeMode <> opeMode THEN
    local_prevOpeMode := opeMode;
    local_manualA := FALSE;
    local_manualB := FALSE;
    local_manualC := FALSE;
    local_manualD := FALSE;
    local_manualMix := FALSE;
    local_autoState := AUTO_IDLE;
    local_firstAutoScan := FALSE;
    local_mixArmed := FALSE;
END_IF;

IF NOT estop THEN
    valveARun := FALSE;
    valveBRun := FALSE;
    valveCRun := FALSE;
    valveDRun := FALSE;
    mixMotorRun := FALSE;

    local_manualA := FALSE;
    local_manualB := FALSE;
    local_manualC := FALSE;
    local_manualD := FALSE;
    local_manualMix := FALSE;
    local_autoState := AUTO_IDLE;
    local_firstAutoScan := FALSE;
    local_mixArmed := FALSE;
    RETURN;
END_IF;

IF opeMode THEN
    IF local_autoStartEdge THEN
        local_autoState := AUTO_FILL_A;
        local_firstAutoScan := TRUE;
        local_mixArmed := FALSE;
    END_IF;

    IF NOT local_firstAutoScan THEN
        IF local_autoState = AUTO_FILL_A THEN
            IF levelSensor >= 50 THEN
                local_autoState := AUTO_FILL_B;
            END_IF;
        ELSIF local_autoState = AUTO_FILL_B THEN
            IF levelSensor >= 80 THEN
                IF processMode THEN
                    local_autoState := AUTO_FILL_C;
                ELSE
                    local_autoState := AUTO_MIX;
                END_IF;
            END_IF;
        ELSIF local_autoState = AUTO_FILL_C THEN
            IF levelSensor >= 100 THEN
                local_autoState := AUTO_MIX;
            END_IF;
        ELSIF local_autoState = AUTO_MIX THEN
            IF local_mixArmed AND mixMotorComplete THEN
                local_autoState := AUTO_DELIVER;
            END_IF;
        END_IF;
    END_IF;

    IF local_autoState = AUTO_MIX THEN
        IF NOT mixMotorComplete THEN
            local_mixArmed := TRUE;
        END_IF;
    ELSE
        local_mixArmed := FALSE;
    END_IF;

    CASE local_autoState OF
        AUTO_IDLE:
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;

        AUTO_FILL_A:
            valveARun := TRUE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;

        AUTO_FILL_B:
            valveARun := FALSE;
            valveBRun := TRUE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;

        AUTO_FILL_C:
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := TRUE;
            valveDRun := FALSE;
            mixMotorRun := FALSE;

        AUTO_MIX:
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := FALSE;
            mixMotorRun := TRUE;

        AUTO_DELIVER:
            valveARun := FALSE;
            valveBRun := FALSE;
            valveCRun := FALSE;
            valveDRun := TRUE;
            mixMotorRun := FALSE;
    END_CASE;

    local_firstAutoScan := FALSE;
ELSE
    IF local_edgeA THEN
        local_manualA := NOT local_manualA;
    END_IF;

    IF local_edgeB THEN
        local_manualB := NOT local_manualB;
    END_IF;

    IF local_edgeC THEN
        local_manualC := NOT local_manualC;
    END_IF;

    IF local_edgeD THEN
        local_manualD := NOT local_manualD;
    END_IF;

    IF local_edgeMix THEN
        local_manualMix := NOT local_manualMix;
    END_IF;

    valveARun := local_manualA;
    valveBRun := local_manualB;
    valveCRun := local_manualC;
    valveDRun := local_manualD;
    mixMotorRun := local_manualMix;
END_IF;
END_FUNCTION_BLOCK