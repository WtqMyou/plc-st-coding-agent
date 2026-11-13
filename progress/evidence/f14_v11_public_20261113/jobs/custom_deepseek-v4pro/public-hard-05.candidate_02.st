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
VAR CONSTANT
    cStepDown1 : INT := 1;
    cStepGrip : INT := 2;
    cStepUp1 : INT := 3;
    cStepRight : INT := 4;
    cStepDown2 : INT := 5;
    cStepRelease : INT := 6;
    cStepUp2 : INT := 7;
    cStepLeft : INT := 8;
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
        cStepDown1: sdDone := DownLimitSwitch;
        cStepGrip: sdDone := GripLimitSwitch;
        cStepUp1: sdDone := UpLimitSwitch;
        cStepRight: sdDone := RightLimitSwitch;
        cStepDown2: sdDone := DownLimitSwitch;
        cStepRelease: sdDone := ReleaseLimitSwitch;
        cStepUp2: sdDone := UpLimitSwitch;
        cStepLeft: sdDone := LeftLimitSwitch;
    ELSE
        sdDone := TRUE;
    END_CASE;

    IF EmergencyStop AND startTrig.Q AND sdDone THEN
        IF sdStep >= cStepLeft THEN
            sdStep := cStepDown1;
        ELSE
            sdStep := sdStep + 1;
        END_IF;
    END_IF;

    CASE sdStep OF
        cStepDown1: tmpMoveDown := NOT DownLimitSwitch;
        cStepGrip: tmpActivateGrip := NOT GripLimitSwitch;
        cStepUp1: tmpMoveUp := NOT UpLimitSwitch;
        cStepRight: tmpMoveRight := NOT RightLimitSwitch;
        cStepDown2: tmpMoveDown := NOT DownLimitSwitch;
        cStepRelease: tmpActivateRelease := NOT ReleaseLimitSwitch;
        cStepUp2: tmpMoveUp := NOT UpLimitSwitch;
        cStepLeft: tmpMoveLeft := NOT LeftLimitSwitch;
    ELSE
        (* no automatic output *)
    END_CASE;

ELSIF SingleCycleMode OR ContinuousMode THEN
    IF EmergencyStop AND startTrig.Q AND (autoStep = 0) THEN
        autoStep := cStepDown1;
    END_IF;

    CASE autoStep OF
        cStepDown1: autoDone := DownLimitSwitch;
        cStepGrip: autoDone := GripLimitSwitch;
        cStepUp1: autoDone := UpLimitSwitch;
        cStepRight: autoDone := RightLimitSwitch;
        cStepDown2: autoDone := DownLimitSwitch;
        cStepRelease: autoDone := ReleaseLimitSwitch;
        cStepUp2: autoDone := UpLimitSwitch;
        cStepLeft: autoDone := LeftLimitSwitch;
    ELSE
        autoDone := TRUE;
    END_CASE;

    IF EmergencyStop AND (autoStep <> 0) AND autoDone THEN
        IF SingleCycleMode THEN
            IF autoStep < cStepLeft THEN
                autoStep := autoStep + 1;
            ELSE
                autoStep := 0;
            END_IF;
        ELSIF ContinuousMode THEN
            IF autoStep < cStepLeft THEN
                autoStep := autoStep + 1;
            ELSE
                autoStep := cStepDown1;
            END_IF;
        END_IF;
    END_IF;

    CASE autoStep OF
        cStepDown1: tmpMoveDown := NOT DownLimitSwitch;
        cStepGrip: tmpActivateGrip := NOT GripLimitSwitch;
        cStepUp1: tmpMoveUp := NOT UpLimitSwitch;
        cStepRight: tmpMoveRight := NOT RightLimitSwitch;
        cStepDown2: tmpMoveDown := NOT DownLimitSwitch;
        cStepRelease: tmpActivateRelease := NOT ReleaseLimitSwitch;
        cStepUp2: tmpMoveUp := NOT UpLimitSwitch;
        cStepLeft: tmpMoveLeft := NOT LeftLimitSwitch;
    ELSE
        (* idle/no output *)
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