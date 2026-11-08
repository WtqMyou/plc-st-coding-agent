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
    Step : INT := 1;
    StartPrev : BOOL := FALSE;
    IsRunning : BOOL := FALSE;
END_VAR

    // Edge detection for Start button
    VAR
        StartRisingEdge : BOOL;
    END_VAR
    StartRisingEdge := Start AND NOT StartPrev;
    StartPrev := Start;

    // Emergency stop - highest priority
    IF NOT EmergencyStop THEN
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;
        RETURN;
    END_IF

    // Mode initialization
    IF SingleStepMode THEN
        IF NOT IsRunning THEN
            IF StartRisingEdge THEN
                Step := 1;
                IsRunning := TRUE;
            END_IF;
        END_IF;
    ELSIF SingleCycleMode THEN
        IF NOT IsRunning THEN
            IF StartRisingEdge THEN
                Step := 1;
                IsRunning := TRUE;
            END_IF;
        END_IF;
    ELSIF ContinuousMode THEN
        IF NOT IsRunning THEN
            IF StartRisingEdge THEN
                Step := 1;
                IsRunning := TRUE;
            END_IF;
        END_IF;
    ELSE
        IsRunning := FALSE;
    END_IF;

    // Execute current step in automatic modes
    IF IsRunning THEN
        CASE Step OF
            1: // MoveDown
                MoveDown := TRUE;
                IF DownLimitSwitch THEN
                    MoveDown := FALSE;
                    IF Step < 8 THEN
                        Step := Step + 1;
                    ELSE
                        Step := 1;
                    END_IF;
                    IF SingleStepMode THEN
                        IsRunning := FALSE;
                    END_IF;
                END_IF;

            2: // ActivateGrip
                ActivateGrip := TRUE;
                IF GripLimitSwitch THEN
                    ActivateGrip := FALSE;
                    IF Step < 8 THEN
                        Step := Step + 1;
                    ELSE
                        Step := 1;
                    END_IF;
                    IF SingleStepMode THEN
                        IsRunning := FALSE;
                    END_IF;
                END_IF;

            3: // MoveUp
                MoveUp := TRUE;
                IF UpLimitSwitch THEN
                    MoveUp := FALSE;
                    IF Step < 8 THEN
                        Step := Step + 1;
                    ELSE
                        Step := 1;
                    END_IF;
                    IF SingleStepMode THEN
                        IsRunning := FALSE;
                    END_IF;
                END_IF;

            4: // MoveRight
                MoveRight := TRUE;
                IF RightLimitSwitch THEN
                    MoveRight := FALSE;
                    IF Step < 8 THEN
                        Step := Step + 1;
                    ELSE
                        Step := 1;
                    END_IF;
                    IF SingleStepMode THEN
                        IsRunning := FALSE;
                    END_IF;
                END_IF;

            5: // MoveDown
                MoveDown := TRUE;
                IF DownLimitSwitch THEN
                    MoveDown := FALSE;
                    IF Step < 8 THEN
                        Step := Step + 1;
                    ELSE
                        Step := 1;
                    END_IF;
                    IF SingleStepMode THEN
                        IsRunning := FALSE;
                    END_IF;
                END_IF;

            6: // ActivateRelease
                ActivateRelease := TRUE;
                IF ReleaseLimitSwitch THEN
                    ActivateRelease := FALSE;
                    IF Step < 8 THEN
                        Step := Step + 1;
                    ELSE
                        Step := 1;
                    END_IF;
                    IF SingleStepMode THEN
                        IsRunning := FALSE;
                    END_IF;
                END_IF;

            7: // MoveUp
                MoveUp := TRUE;
                IF UpLimitSwitch THEN
                    MoveUp := FALSE;
                    IF Step < 8 THEN
                        Step := Step + 1;
                    ELSE
                        Step := 1;
                    END_IF;
                    IF SingleStepMode THEN
                        IsRunning := FALSE;
                    END_IF;
                END_IF;

            8: // MoveLeft
                MoveLeft := TRUE;
                IF LeftLimitSwitch THEN
                    MoveLeft := FALSE;
                    Step := 1;
                    IF SingleStepMode THEN
                        IsRunning := FALSE;
                    END_IF;
                END_IF;
        END_CASE;

    // Manual mode
    ELSIF ManualMode THEN
        // Down
        MoveDown := DownButton AND NOT DownLimitSwitch;
        // Up
        MoveUp := UpButton AND NOT UpLimitSwitch;
        // Left
        MoveLeft := LeftButton AND NOT LeftLimitSwitch;
        // Right
        MoveRight := RightButton AND NOT RightLimitSwitch;
        // Grip
        ActivateGrip := GripButton AND NOT GripLimitSwitch;
        // Release
        ActivateRelease := ReleaseButton AND NOT ReleaseLimitSwitch;
    END_IF;

END_FUNCTION_BLOCK