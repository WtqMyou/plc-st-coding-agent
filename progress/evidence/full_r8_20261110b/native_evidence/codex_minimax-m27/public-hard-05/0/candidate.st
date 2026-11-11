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
    Step : INT := 0;
    StartPrev : BOOL := FALSE;
    InAutoOperation : BOOL := FALSE;
    WaitForNextStart : BOOL := FALSE;
END_VAR

IF ManualMode THEN
    MoveDown := FALSE;
    MoveUp := FALSE;
    MoveLeft := FALSE;
    MoveRight := FALSE;
    ActivateGrip := FALSE;
    ActivateRelease := FALSE;
    Step := 0;
    InAutoOperation := FALSE;
    WaitForNextStart := FALSE;
    StartPrev := Start;
ELSIF EmergencyStop THEN
    IF InAutoOperation THEN
        IF WaitForNextStart THEN
            IF Start AND NOT StartPrev THEN
                WaitForNextStart := FALSE;
                Step := Step + 1;
            END_IF
        ELSIF Step = 1 THEN
            MoveDown := NOT DownLimitSwitch;
            MoveUp := FALSE;
            MoveLeft := FALSE;
            MoveRight := FALSE;
            ActivateGrip := FALSE;
            ActivateRelease := FALSE;
            IF DownLimitSwitch THEN
                MoveDown := FALSE;
                Step := 2;
                IF SingleStepMode THEN
                    WaitForNextStart := TRUE;
                END_IF
            END_IF
        ELSIF Step = 2 THEN
            MoveDown := FALSE;
            MoveUp := FALSE;
            MoveLeft := FALSE;
            MoveRight := FALSE;
            ActivateGrip := NOT GripLimitSwitch;
            ActivateRelease := FALSE;
            IF GripLimitSwitch THEN
                ActivateGrip := FALSE;
                Step := 3;
                IF SingleStepMode THEN
                    WaitForNextStart := TRUE;
                END_IF
            END_IF
        ELSIF Step = 3 THEN
            MoveDown := FALSE;
            MoveUp := NOT UpLimitSwitch;
            MoveLeft := FALSE;
            MoveRight := FALSE;
            ActivateGrip := FALSE;
            ActivateRelease := FALSE;
            IF UpLimitSwitch THEN
                MoveUp := FALSE;
                Step := 4;
                IF SingleStepMode THEN
                    WaitForNextStart := TRUE;
                END_IF
            END_IF
        ELSIF Step = 4 THEN
            MoveDown := FALSE;
            MoveUp := FALSE;
            MoveLeft := FALSE;
            MoveRight := NOT RightLimitSwitch;
            ActivateGrip := FALSE;
            ActivateRelease := FALSE;
            IF RightLimitSwitch THEN
                MoveRight := FALSE;
                Step := 5;
                IF SingleStepMode THEN
                    WaitForNextStart := TRUE;
                END_IF
            END_IF
        ELSIF Step = 5 THEN
            MoveDown := NOT DownLimitSwitch;
            MoveUp := FALSE;
            MoveLeft := FALSE;
            MoveRight := FALSE;
            ActivateGrip := FALSE;
            ActivateRelease := FALSE;
            IF DownLimitSwitch THEN
                MoveDown := FALSE;
                Step := 6;
                IF SingleStepMode THEN
                    WaitForNextStart := TRUE;
                END_IF
            END_IF
        ELSIF Step = 6 THEN
            MoveDown := FALSE;
            MoveUp := FALSE;
            MoveLeft := FALSE;
            MoveRight := FALSE;
            ActivateGrip := FALSE;
            ActivateRelease := NOT ReleaseLimitSwitch;
            IF ReleaseLimitSwitch THEN
                ActivateRelease := FALSE;
                Step := 7;
                IF SingleStepMode THEN
                    WaitForNextStart := TRUE;
                END_IF
            END_IF
        ELSIF Step = 7 THEN
            MoveDown := FALSE;
            MoveUp := NOT UpLimitSwitch;
            MoveLeft := FALSE;
            MoveRight := FALSE;
            ActivateGrip := FALSE;
            ActivateRelease := FALSE;
            IF UpLimitSwitch THEN
                MoveUp := FALSE;
                Step := 8;
                IF SingleStepMode THEN
                    WaitForNextStart := TRUE;
                END_IF
            END_IF
        ELSIF Step = 8 THEN
            MoveDown := FALSE;
            MoveUp := FALSE;
            MoveLeft := NOT LeftLimitSwitch;
            MoveRight := FALSE;
            ActivateGrip := FALSE;
            ActivateRelease := FALSE;
            IF LeftLimitSwitch THEN
                MoveLeft := FALSE;
                InAutoOperation := FALSE;
                IF SingleCycleMode THEN
                    Step := 0;
                ELSIF ContinuousMode THEN
                    Step := 1;
                ELSE
                    Step := 0;
                END_IF
                IF SingleStepMode THEN
                    WaitForNextStart := TRUE;
                END_IF
            END_IF
        END_IF
    ELSIF Start AND NOT StartPrev AND (SingleStepMode OR SingleCycleMode OR ContinuousMode) THEN
        InAutoOperation := TRUE;
        WaitForNextStart := FALSE;
        Step := 1;
        MoveDown := NOT DownLimitSwitch;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;
    END_IF
    StartPrev := Start;
ELSE
    MoveDown := FALSE;
    MoveUp := FALSE;
    MoveLeft := FALSE;
    MoveRight := FALSE;
    ActivateGrip := FALSE;
    ActivateRelease := FALSE;
    Step := 0;
    InAutoOperation := FALSE;
    WaitForNextStart := FALSE;
    StartPrev := FALSE;
END_IF

IF ManualMode AND EmergencyStop THEN
    MoveDown := DownButton AND NOT UpButton AND NOT DownLimitSwitch;
    MoveUp := UpButton AND NOT DownButton AND NOT UpLimitSwitch;
    MoveLeft := LeftButton AND NOT RightButton AND NOT LeftLimitSwitch;
    MoveRight := RightButton AND NOT LeftButton AND NOT RightLimitSwitch;
    ActivateGrip := GripButton AND NOT ReleaseButton AND NOT GripLimitSwitch;
    ActivateRelease := ReleaseButton AND NOT GripButton AND NOT ReleaseLimitSwitch;
END_IF
END_FUNCTION_BLOCK