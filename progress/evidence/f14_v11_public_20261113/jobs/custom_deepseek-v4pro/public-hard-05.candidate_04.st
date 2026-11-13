(* ENGINEERING_CONTRACT
Manual: moving/grip/release outputs are combinational from corresponding button AND NOT corresponding limit switch; releasing the button clears the output. PUB001, PUB005.
SingleStep: rising Start advances only when idle or current step limit reached; each step holds its output until its limit, then waits for next Start. After step 8, next Start goes to step 1. PUB002.
SingleCycle: rising Start starts step 1; each step auto-advances on its completion limit, then stops at step 0 after step 8. PUB003.
Continuous: rising Start starts step 1; auto-advances and loops 8->1. PUB004.
EmergencyStop=FALSE forces all outputs FALSE and freezes automatic state changes. No reset is inferred. PUB005.
Completion feedback uses DownLimitSwitch, UpLimitSwitch, LeftLimitSwitch, RightLimitSwitch, GripLimitSwitch, ReleaseLimitSwitch. Unspecified mode-change behavior preserves the automatic step state.
*)
(* CONTRACT_RULES [] *)
FUNCTION_BLOCK FB_MechanicalArmControl
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
    startTrig : R_TRIG;
    sdStep : INT := 0;
    autoStep : INT := 0;
    sdDone : BOOL;
    autoDone : BOOL;
    tmpMoveDown : BOOL;
    tmpMoveUp : BOOL;
    tmpMoveLeft : BOOL;
    tmpMoveRight : BOOL;
    tmpActivateGrip : BOOL;
    tmpActivateRelease : BOOL;
END_VAR

startTrig(CLK := Start);

tmpMoveDown := FALSE;
tmpMoveUp := FALSE;
tmpMoveLeft := FALSE;
tmpMoveRight := FALSE;
tmpActivateGrip := FALSE;
tmpActivateRelease := FALSE;

IF ManualMode THEN
    tmpMoveDown := DownButton AND NOT DownLimitSwitch;
    tmpMoveUp := UpButton AND NOT UpLimitSwitch;
    tmpMoveLeft := LeftButton AND NOT LeftLimitSwitch;
    tmpMoveRight := RightButton AND NOT RightLimitSwitch;
    tmpActivateGrip := GripButton AND NOT GripLimitSwitch;
    tmpActivateRelease := ReleaseButton AND NOT ReleaseLimitSwitch;

ELSIF SingleStepMode THEN
    CASE sdStep OF
        1: sdDone := DownLimitSwitch;
        2: sdDone := GripLimitSwitch;
        3: sdDone := UpLimitSwitch;
        4: sdDone := RightLimitSwitch;
        5: sdDone := DownLimitSwitch;
        6: sdDone := ReleaseLimitSwitch;
        7: sdDone := UpLimitSwitch;
        8: sdDone := LeftLimitSwitch;
    ELSE
        sdDone := TRUE;
    END_CASE;

    IF EmergencyStop AND startTrig.Q AND sdDone THEN
        IF sdStep >= 8 THEN
            sdStep := 1;
        ELSE
            sdStep := sdStep + 1;
        END_IF;
    END_IF;

    CASE sdStep OF
        1: tmpMoveDown := NOT DownLimitSwitch;
        2: tmpActivateGrip := NOT GripLimitSwitch;
        3: tmpMoveUp := NOT UpLimitSwitch;
        4: tmpMoveRight := NOT RightLimitSwitch;
        5: tmpMoveDown := NOT DownLimitSwitch;
        6: tmpActivateRelease := NOT ReleaseLimitSwitch;
        7: tmpMoveUp := NOT UpLimitSwitch;
        8: tmpMoveLeft := NOT LeftLimitSwitch;
    END_CASE;

ELSIF (SingleCycleMode OR ContinuousMode) THEN
    IF EmergencyStop AND startTrig.Q AND (autoStep = 0) THEN
        autoStep := 1;
    END_IF;

    CASE autoStep OF
        1: autoDone := DownLimitSwitch;
        2: autoDone := GripLimitSwitch;
        3: autoDone := UpLimitSwitch;
        4: autoDone := RightLimitSwitch;
        5: autoDone := DownLimitSwitch;
        6: autoDone := ReleaseLimitSwitch;
        7: autoDone := UpLimitSwitch;
        8: autoDone := LeftLimitSwitch;
    ELSE
        autoDone := TRUE;
    END_CASE;

    IF EmergencyStop AND (autoStep <> 0) AND autoDone THEN
        IF SingleCycleMode THEN
            IF autoStep < 8 THEN
                autoStep := autoStep + 1;
            ELSE
                autoStep := 0;
            END_IF;
        ELSIF ContinuousMode THEN
            IF autoStep < 8 THEN
                autoStep := autoStep + 1;
            ELSE
                autoStep := 1;
            END_IF;
        END_IF;
    END_IF;

    CASE autoStep OF
        1: tmpMoveDown := NOT DownLimitSwitch;
        2: tmpActivateGrip := NOT GripLimitSwitch;
        3: tmpMoveUp := NOT UpLimitSwitch;
        4: tmpMoveRight := NOT RightLimitSwitch;
        5: tmpMoveDown := NOT DownLimitSwitch;
        6: tmpActivateRelease := NOT ReleaseLimitSwitch;
        7: tmpMoveUp := NOT UpLimitSwitch;
        8: tmpMoveLeft := NOT LeftLimitSwitch;
    END_CASE;

END_IF;

IF NOT EmergencyStop THEN
    MoveDown := FALSE;
    MoveUp := FALSE;
    MoveLeft := FALSE;
    MoveRight := FALSE;
    ActivateGrip := FALSE;
    ActivateRelease := FALSE;
ELSE
    MoveDown := tmpMoveDown;
    MoveUp := tmpMoveUp;
    MoveLeft := tmpMoveLeft;
    MoveRight := tmpMoveRight;
    ActivateGrip := tmpActivateGrip;
    ActivateRelease := tmpActivateRelease;
END_IF;

END_FUNCTION_BLOCK