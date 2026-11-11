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
    MoveDown : BOOL;
    MoveUp : BOOL;
    MoveLeft : BOOL;
    MoveRight : BOOL;
    ActivateGrip : BOOL;
    ActivateRelease : BOOL;
END_VAR
VAR
    StartPrev : BOOL := FALSE;
    PrevManualMode : BOOL := FALSE;
    PrevSingleStepMode : BOOL := FALSE;
    PrevSingleCycleMode : BOOL := FALSE;
    PrevContinuousMode : BOOL := FALSE;
    ModeChanged : BOOL;
    StartPulse : BOOL;
    AutoStep : INT := 0;
END_VAR

MoveDown := FALSE;
MoveUp := FALSE;
MoveLeft := FALSE;
MoveRight := FALSE;
ActivateGrip := FALSE;
ActivateRelease := FALSE;

StartPulse := Start AND NOT StartPrev;
ModeChanged := (ManualMode <> PrevManualMode)
                OR (SingleStepMode <> PrevSingleStepMode)
                OR (SingleCycleMode <> PrevSingleCycleMode)
                OR (ContinuousMode <> PrevContinuousMode);

IF ModeChanged THEN
    AutoStep := 0;
END_IF;

IF EmergencyStop THEN
    IF ManualMode THEN
        MoveDown := DownButton AND NOT UpButton AND NOT DownLimitSwitch;
        MoveUp := UpButton AND NOT DownButton AND NOT UpLimitSwitch;
        MoveLeft := LeftButton AND NOT RightButton AND NOT LeftLimitSwitch;
        MoveRight := RightButton AND NOT LeftButton AND NOT RightLimitSwitch;
        ActivateGrip := GripButton AND NOT ReleaseButton AND NOT GripLimitSwitch;
        ActivateRelease := ReleaseButton AND NOT GripButton AND NOT ReleaseLimitSwitch;
    ELSIF SingleStepMode THEN
        IF AutoStep = 0 THEN
            IF StartPulse THEN
                AutoStep := 1;
            END_IF;
        END_IF;

        CASE AutoStep OF
            1:
                IF DownLimitSwitch THEN
                    AutoStep := 0;
                ELSE
                    MoveDown := TRUE;
                END_IF;
            2:
                IF GripLimitSwitch THEN
                    AutoStep := 0;
                ELSE
                    ActivateGrip := TRUE;
                END_IF;
            3:
                IF UpLimitSwitch THEN
                    AutoStep := 0;
                ELSE
                    MoveUp := TRUE;
                END_IF;
            4:
                IF RightLimitSwitch THEN
                    AutoStep := 0;
                ELSE
                    MoveRight := TRUE;
                END_IF;
            5:
                IF DownLimitSwitch THEN
                    AutoStep := 0;
                ELSE
                    MoveDown := TRUE;
                END_IF;
            6:
                IF ReleaseLimitSwitch THEN
                    AutoStep := 0;
                ELSE
                    ActivateRelease := TRUE;
                END_IF;
            7:
                IF UpLimitSwitch THEN
                    AutoStep := 0;
                ELSE
                    MoveUp := TRUE;
                END_IF;
            8:
                IF LeftLimitSwitch THEN
                    AutoStep := 0;
                ELSE
                    MoveLeft := TRUE;
                END_IF;
        END_CASE;
    ELSIF SingleCycleMode OR ContinuousMode THEN
        IF AutoStep = 0 THEN
            IF StartPulse THEN
                AutoStep := 1;
            END_IF;
        END_IF;

        IF AutoStep = 1 AND DownLimitSwitch THEN
            AutoStep := 2;
        END_IF;
        IF AutoStep = 2 AND GripLimitSwitch THEN
            AutoStep := 3;
        END_IF;
        IF AutoStep = 3 AND UpLimitSwitch THEN
            AutoStep := 4;
        END_IF;
        IF AutoStep = 4 AND RightLimitSwitch THEN
            AutoStep := 5;
        END_IF;
        IF AutoStep = 5 AND DownLimitSwitch THEN
            AutoStep := 6;
        END_IF;
        IF AutoStep = 6 AND ReleaseLimitSwitch THEN
            AutoStep := 7;
        END_IF;
        IF AutoStep = 7 AND UpLimitSwitch THEN
            AutoStep := 8;
        END_IF;
        IF AutoStep = 8 AND LeftLimitSwitch THEN
            IF ContinuousMode THEN
                AutoStep := 1;
            ELSE
                AutoStep := 0;
            END_IF;
        END_IF;

        CASE AutoStep OF
            1:
                IF NOT DownLimitSwitch THEN
                    MoveDown := TRUE;
                END_IF;
            2:
                IF NOT GripLimitSwitch THEN
                    ActivateGrip := TRUE;
                END_IF;
            3:
                IF NOT UpLimitSwitch THEN
                    MoveUp := TRUE;
                END_IF;
            4:
                IF NOT RightLimitSwitch THEN
                    MoveRight := TRUE;
                END_IF;
            5:
                IF NOT DownLimitSwitch THEN
                    MoveDown := TRUE;
                END_IF;
            6:
                IF NOT ReleaseLimitSwitch THEN
                    ActivateRelease := TRUE;
                END_IF;
            7:
                IF NOT UpLimitSwitch THEN
                    MoveUp := TRUE;
                END_IF;
            8:
                IF NOT LeftLimitSwitch THEN
                    MoveLeft := TRUE;
                END_IF;
        END_CASE;
    END_IF;
END_IF;

PrevManualMode := ManualMode;
PrevSingleStepMode := SingleStepMode;
PrevSingleCycleMode := SingleCycleMode;
PrevContinuousMode := ContinuousMode;
StartPrev := Start;
END_FUNCTION_BLOCK