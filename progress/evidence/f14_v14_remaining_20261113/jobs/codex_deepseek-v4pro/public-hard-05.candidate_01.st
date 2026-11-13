(* ENGINEERING_CONTRACT
   Manual axis output: ON while its button=1, opposite command inactive, and its limit=0; OFF on release/limit (PUB001).
   Manual grip/release: ON while button=1, opposite inactive, and its limit=0; OFF on release/limit (PUB001).
   Single-step: Start edge activates next index 0..7/wraps; output held until switch; next Start advances (PUB002-PUB003).
   Single-cycle: Start edge runs 0..7; holds each output until completion; stops after left; next Start restarts (PUB004).
   Continuous: Start edge runs 0..7 and loops after left while mode selected (PUB005).
   Emergency: EmergencyStop=FALSE overrides all outputs and freezes start/progression; state is retained (PUB006).
   Index completion: 0/4 DownLimit, 1 GripLimit, 2/6 UpLimit, 3 RightLimit, 5 ReleaseLimit, 7 LeftLimit.
   Same-scan priority: E-stop highest; a feedback-completed action cannot energize on its completion scan; next action starts next scan.
   Unspecified: post-E-stop resumption uses retained state; mode changes outside a mode retain sequence state.
*)
(* CONTRACT_RULES [] *)

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
    tmp_startEdge : R_TRIG;
    tmp_autoMode : BOOL;
    tmp_autoActive : BOOL := FALSE;
    tmp_currentStep : INT := 0;
    tmp_singleNextStep : INT := 0;
    tmp_targetReached : BOOL;

    tmp_manualDownReq : BOOL;
    tmp_manualUpReq : BOOL;
    tmp_manualLeftReq : BOOL;
    tmp_manualRightReq : BOOL;
    tmp_manualGripReq : BOOL;
    tmp_manualReleaseReq : BOOL;

    tmp_autoDown : BOOL;
    tmp_autoUp : BOOL;
    tmp_autoLeft : BOOL;
    tmp_autoRight : BOOL;
    tmp_autoGrip : BOOL;
    tmp_autoRelease : BOOL;

    tmp_down : BOOL;
    tmp_up : BOOL;
    tmp_left : BOOL;
    tmp_right : BOOL;
    tmp_grip : BOOL;
    tmp_release : BOOL;
END_VAR

tmp_startEdge(CLK := Start);

tmp_manualDownReq := ManualMode AND DownButton AND NOT DownLimitSwitch;
tmp_manualUpReq := ManualMode AND UpButton AND NOT UpLimitSwitch;
tmp_manualLeftReq := ManualMode AND LeftButton AND NOT LeftLimitSwitch;
tmp_manualRightReq := ManualMode AND RightButton AND NOT RightLimitSwitch;
tmp_manualGripReq := ManualMode AND GripButton AND NOT GripLimitSwitch;
tmp_manualReleaseReq := ManualMode AND ReleaseButton AND NOT ReleaseLimitSwitch;

tmp_autoMode := SingleStepMode OR SingleCycleMode OR ContinuousMode;

IF EmergencyStop AND tmp_startEdge.Q THEN
    IF SingleStepMode THEN
        IF NOT tmp_autoActive THEN
            tmp_currentStep := tmp_singleNextStep;
            tmp_singleNextStep := (tmp_singleNextStep + 1) MOD 8;
            tmp_autoActive := TRUE;
        END_IF;
    ELSIF SingleCycleMode THEN
        IF NOT tmp_autoActive THEN
            tmp_currentStep := 0;
            tmp_autoActive := TRUE;
        END_IF;
    ELSIF ContinuousMode THEN
        IF NOT tmp_autoActive THEN
            tmp_currentStep := 0;
            tmp_autoActive := TRUE;
        END_IF;
    END_IF;
END_IF;

CASE tmp_currentStep OF
    0, 4:
        tmp_targetReached := DownLimitSwitch;
    1:
        tmp_targetReached := GripLimitSwitch;
    2, 6:
        tmp_targetReached := UpLimitSwitch;
    3:
        tmp_targetReached := RightLimitSwitch;
    5:
        tmp_targetReached := ReleaseLimitSwitch;
    7:
        tmp_targetReached := LeftLimitSwitch;
ELSE
    tmp_targetReached := FALSE;
END_CASE;

tmp_autoDown := tmp_autoMode AND tmp_autoActive AND ((tmp_currentStep = 0) OR (tmp_currentStep = 4)) AND NOT DownLimitSwitch;
tmp_autoGrip := tmp_autoMode AND tmp_autoActive AND (tmp_currentStep = 1) AND NOT GripLimitSwitch;
tmp_autoUp := tmp_autoMode AND tmp_autoActive AND ((tmp_currentStep = 2) OR (tmp_currentStep = 6)) AND NOT UpLimitSwitch;
tmp_autoRight := tmp_autoMode AND tmp_autoActive AND (tmp_currentStep = 3) AND NOT RightLimitSwitch;
tmp_autoRelease := tmp_autoMode AND tmp_autoActive AND (tmp_currentStep = 5) AND NOT ReleaseLimitSwitch;
tmp_autoLeft := tmp_autoMode AND tmp_autoActive AND (tmp_currentStep = 7) AND NOT LeftLimitSwitch;

tmp_down := tmp_manualDownReq OR tmp_autoDown;
tmp_up := tmp_manualUpReq OR tmp_autoUp;
tmp_left := tmp_manualLeftReq OR tmp_autoLeft;
tmp_right := tmp_manualRightReq OR tmp_autoRight;
tmp_grip := tmp_manualGripReq OR tmp_autoGrip;
tmp_release := tmp_manualReleaseReq OR tmp_autoRelease;

MoveDown := tmp_down AND NOT tmp_up AND EmergencyStop;
MoveUp := tmp_up AND NOT tmp_down AND EmergencyStop;
MoveLeft := tmp_left AND NOT tmp_right AND EmergencyStop;
MoveRight := tmp_right AND NOT tmp_left AND EmergencyStop;
ActivateGrip := tmp_grip AND NOT tmp_release AND EmergencyStop;
ActivateRelease := tmp_release AND NOT tmp_grip AND EmergencyStop;

IF EmergencyStop AND tmp_autoMode AND tmp_autoActive AND tmp_targetReached THEN
    IF SingleStepMode THEN
        tmp_autoActive := FALSE;
    ELSIF SingleCycleMode THEN
        IF tmp_currentStep >= 7 THEN
            tmp_autoActive := FALSE;
            tmp_currentStep := 0;
        ELSE
            tmp_currentStep := tmp_currentStep + 1;
        END_IF;
    ELSIF ContinuousMode THEN
        IF tmp_currentStep >= 7 THEN
            tmp_currentStep := 0;
        ELSE
            tmp_currentStep := tmp_currentStep + 1;
        END_IF;
    END_IF;
END_IF;

END_FUNCTION_BLOCK