FUNCTION_BLOCK MechanicalArmControl
VAR_INPUT
    ManualMode : BOOL;
    SingleStepMode : BOOL;
    SingleCycleMode : BOOL;
    ContinuousMode : BOOL;
    EmergencyStop : BOOL;
    Start : BOOL;
    DownButton : BOOL;
    UpButton : BOOL;
    LeftButton : BOOL;
    RightButton : BOOL;
    GripButton : BOOL;
    ReleaseButton : BOOL;
    DownLimitSwitch : BOOL;
    UpLimitSwitch : BOOL;
    LeftLimitSwitch : BOOL;
    RightLimitSwitch : BOOL;
    GripLimitSwitch : BOOL;
    ReleaseLimitSwitch : BOOL;
END_VAR
VAR_OUTPUT
    MoveDown : BOOL;
    MoveUp : BOOL;
    MoveLeft : BOOL;
    MoveRight : BOOL;
    ActivateGrip : BOOL;
    ActivateRelease : BOOL;
END_VAR
VAR
    local_StartRTrig : R_TRIG;
    local_StartEdge : BOOL;
    local_AutoActive : BOOL := FALSE;
    local_AutoStep : INT := 0;
    local_StepComplete : BOOL;
    local_DesiredMoveDown : BOOL;
    local_DesiredMoveUp : BOOL;
    local_DesiredMoveLeft : BOOL;
    local_DesiredMoveRight : BOOL;
    local_DesiredActivateGrip : BOOL;
    local_DesiredActivateRelease : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   Manual outputs: active in ManualMode while button=1 and limit=0;
   deactivate on button release, limit reached, or EmergencyStop=FALSE (PUB001, PUB005).
   SingleStep: Start edge begins current step; holds until limit; waits for next Start (PUB002, PUB003).
   SingleCycle: Start edge starts step0; automatic step advance on limit; stops after left (PUB003, PUB015-PUB017).
   Continuous: Start edge starts step0; automatically repeats after left (PUB004, PUB015-PUB017).
   E-stop: all outputs FALSE while EmergencyStop=FALSE; state frozen (PUB005).
   Auto steps 0..7: down,grip,up,right,down,release,up,left; completion via corresponding limit.
   Units/type: BOOL only; no timers; retained state local_AutoActive/local_AutoStep.
*)

(* CONTRACT_RULES [] *)

local_StartRTrig(CLK := Start);
local_StartEdge := local_StartRTrig.Q;

IF NOT EmergencyStop THEN
    MoveDown := FALSE;
    MoveUp := FALSE;
    MoveLeft := FALSE;
    MoveRight := FALSE;
    ActivateGrip := FALSE;
    ActivateRelease := FALSE;
    RETURN;
END_IF;

local_DesiredMoveDown := FALSE;
local_DesiredMoveUp := FALSE;
local_DesiredMoveLeft := FALSE;
local_DesiredMoveRight := FALSE;
local_DesiredActivateGrip := FALSE;
local_DesiredActivateRelease := FALSE;

IF ManualMode THEN
    IF DownButton AND NOT DownLimitSwitch THEN
        local_DesiredMoveDown := TRUE;
    END_IF;
    IF UpButton AND NOT UpLimitSwitch THEN
        local_DesiredMoveUp := TRUE;
    END_IF;
    IF LeftButton AND NOT LeftLimitSwitch THEN
        local_DesiredMoveLeft := TRUE;
    END_IF;
    IF RightButton AND NOT RightLimitSwitch THEN
        local_DesiredMoveRight := TRUE;
    END_IF;
    IF GripButton AND NOT GripLimitSwitch THEN
        local_DesiredActivateGrip := TRUE;
    END_IF;
    IF ReleaseButton AND NOT ReleaseLimitSwitch THEN
        local_DesiredActivateRelease := TRUE;
    END_IF;

ELSIF SingleStepMode OR SingleCycleMode OR ContinuousMode THEN
    IF SingleStepMode THEN
        IF local_StartEdge AND NOT local_AutoActive THEN
            local_AutoActive := TRUE;
        END_IF;

    ELSIF SingleCycleMode THEN
        IF local_StartEdge THEN
            local_AutoStep := 0;
            local_AutoActive := TRUE;
        END_IF;

    ELSIF ContinuousMode THEN
        IF local_StartEdge THEN
            local_AutoStep := 0;
            local_AutoActive := TRUE;
        END_IF;
    END_IF;

    IF local_AutoActive THEN
        CASE local_AutoStep OF
            0: local_DesiredMoveDown := NOT DownLimitSwitch;
            1: local_DesiredActivateGrip := NOT GripLimitSwitch;
            2: local_DesiredMoveUp := NOT UpLimitSwitch;
            3: local_DesiredMoveRight := NOT RightLimitSwitch;
            4: local_DesiredMoveDown := NOT DownLimitSwitch;
            5: local_DesiredActivateRelease := NOT ReleaseLimitSwitch;
            6: local_DesiredMoveUp := NOT UpLimitSwitch;
            7: local_DesiredMoveLeft := NOT LeftLimitSwitch;
        ELSE
            // no active output for invalid step
        END_CASE;
    END_IF;
END_IF;

MoveDown := local_DesiredMoveDown;
MoveUp := local_DesiredMoveUp;
MoveLeft := local_DesiredMoveLeft;
MoveRight := local_DesiredMoveRight;
ActivateGrip := local_DesiredActivateGrip;
ActivateRelease := local_DesiredActivateRelease;

IF SingleStepMode OR SingleCycleMode OR ContinuousMode THEN
    IF local_AutoActive THEN
        local_StepComplete := FALSE;

        IF (local_AutoStep = 0) OR (local_AutoStep = 4) THEN
            local_StepComplete := DownLimitSwitch;
        ELSIF (local_AutoStep = 1) THEN
            local_StepComplete := GripLimitSwitch;
        ELSIF (local_AutoStep = 2) OR (local_AutoStep = 6) THEN
            local_StepComplete := UpLimitSwitch;
        ELSIF (local_AutoStep = 3) THEN
            local_StepComplete := RightLimitSwitch;
        ELSIF (local_AutoStep = 5) THEN
            local_StepComplete := ReleaseLimitSwitch;
        ELSIF (local_AutoStep = 7) THEN
            local_StepComplete := LeftLimitSwitch;
        END_IF;

        IF local_StepComplete THEN
            IF SingleStepMode THEN
                local_AutoActive := FALSE;
                local_AutoStep := (local_AutoStep + 1) MOD 8;

            ELSIF SingleCycleMode THEN
                IF local_AutoStep < 7 THEN
                    local_AutoStep := local_AutoStep + 1;
                    // local_AutoActive remains TRUE
                ELSE
                    local_AutoActive := FALSE;
                    local_AutoStep := 0;
                END_IF;

            ELSIF ContinuousMode THEN
                local_AutoStep := (local_AutoStep + 1) MOD 8;
                local_AutoActive := TRUE;
            END_IF;
        END_IF;
    END_IF;
END_IF;

END_FUNCTION_BLOCK