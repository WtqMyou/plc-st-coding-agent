FUNCTION_BLOCK FB
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
    MoveDown : BOOL := FALSE;
    MoveUp : BOOL := FALSE;
    MoveLeft : BOOL := FALSE;
    MoveRight : BOOL := FALSE;
    ActivateGrip : BOOL := FALSE;
    ActivateRelease : BOOL := FALSE;
END_VAR

VAR
    StepIndex : INT := 0;
    CurrentStepActive : BOOL := FALSE;
    PrevStart : BOOL := FALSE;
    PrevAutoMode : BOOL := FALSE;
    StartRising : BOOL := FALSE;
    AutoMode : BOOL := FALSE;
END_VAR

    IF NOT EmergencyStop THEN
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;
        RETURN;
    END_IF

    StartRising := Start AND NOT PrevStart;
    PrevStart := Start;

    AutoMode := SingleStepMode OR SingleCycleMode OR ContinuousMode;

    IF AutoMode AND NOT PrevAutoMode THEN
        StepIndex := 0;
        CurrentStepActive := TRUE;
    END_IF;
    PrevAutoMode := AutoMode;

    IF SingleStepMode AND StartRising AND NOT CurrentStepActive THEN
        StepIndex := (StepIndex + 1) MOD 8;
        CurrentStepActive := TRUE;
    END_IF;

    IF (SingleCycleMode OR ContinuousMode) AND CurrentStepActive THEN
        CASE StepIndex OF
            0:
                IF DownLimitSwitch THEN
                    CurrentStepActive := FALSE;
                END_IF
            1:
                IF GripLimitSwitch THEN
                    CurrentStepActive := FALSE;
                END_IF
            2:
                IF UpLimitSwitch THEN
                    CurrentStepActive := FALSE;
                END_IF
            3:
                IF RightLimitSwitch THEN
                    CurrentStepActive := FALSE;
                END_IF
            4:
                IF DownLimitSwitch THEN
                    CurrentStepActive := FALSE;
                END_IF
            5:
                IF ReleaseLimitSwitch THEN
                    CurrentStepActive := FALSE;
                END_IF
            6:
                IF UpLimitSwitch THEN
                    CurrentStepActive := FALSE;
                END_IF
            7:
                IF LeftLimitSwitch THEN
                    CurrentStepActive := FALSE;
                END_IF
        END_CASE
    END_IF;

    IF (SingleCycleMode OR ContinuousMode) AND NOT CurrentStepActive THEN
        IF StepIndex < 7 THEN
            StepIndex := StepIndex + 1;
            CurrentStepActive := TRUE;
        ELSIF ContinuousMode THEN
            StepIndex := 0;
            CurrentStepActive := TRUE;
        END_IF
    END_IF;

    IF AutoMode AND CurrentStepActive THEN
        CASE StepIndex OF
            0:
                MoveDown := NOT DownLimitSwitch;
            1:
                ActivateGrip := NOT GripLimitSwitch;
            2:
                MoveUp := NOT UpLimitSwitch;
            3:
                MoveRight := NOT RightLimitSwitch;
            4:
                MoveDown := NOT DownLimitSwitch;
            5:
                ActivateRelease := NOT ReleaseLimitSwitch;
            6:
                MoveUp := NOT UpLimitSwitch;
            7:
                MoveLeft := NOT LeftLimitSwitch;
        END_CASE
    END_IF;

    IF NOT CurrentStepActive THEN
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;
    END_IF;

    IF ManualMode THEN
        MoveUp := UpButton AND NOT DownButton AND NOT UpLimitSwitch;
        MoveDown := DownButton AND NOT UpButton AND NOT DownLimitSwitch;
        MoveLeft := LeftButton AND NOT RightButton AND NOT LeftLimitSwitch;
        MoveRight := RightButton AND NOT LeftButton AND NOT RightLimitSwitch;
        ActivateGrip := GripButton AND NOT ReleaseButton AND NOT GripLimitSwitch;
        ActivateRelease := ReleaseButton AND NOT GripButton AND NOT ReleaseLimitSwitch;
    END_IF
END_FUNCTION_BLOCK