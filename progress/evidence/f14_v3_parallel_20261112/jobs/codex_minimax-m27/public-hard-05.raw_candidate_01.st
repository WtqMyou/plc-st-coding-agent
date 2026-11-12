FUNCTION_BLOCK MechanicalArmControl
VAR_INPUT
    ManualMode      : BOOL;
    SingleStepMode  : BOOL;
    SingleCycleMode : BOOL;
    ContinuousMode  : BOOL;
    EmergencyStop   : BOOL;
    Start           : BOOL;
    DownButton      : BOOL;
    UpButton        : BOOL;
    LeftButton      : BOOL;
    RightButton     : BOOL;
    GripButton      : BOOL;
    ReleaseButton   : BOOL;
    DownLimitSwitch     : BOOL;
    UpLimitSwitch       : BOOL;
    LeftLimitSwitch     : BOOL;
    RightLimitSwitch    : BOOL;
    GripLimitSwitch     : BOOL;
    ReleaseLimitSwitch  : BOOL;
END_VAR

VAR_OUTPUT
    MoveDown        : BOOL;
    MoveUp          : BOOL;
    MoveLeft        : BOOL;
    MoveRight       : BOOL;
    ActivateGrip    : BOOL;
    ActivateRelease : BOOL;
END_VAR

VAR
    stepNumber       : INT := 0;
    startRisingEdge  : BOOL;
    lastStart        : BOOL := FALSE;
    actionInProgress : BOOL := FALSE;
END_VAR

// Edge detection for Start button
startRisingEdge := Start AND NOT lastStart;
lastStart := Start;

// Emergency stop: highest priority, resets all outputs and state
IF NOT EmergencyStop THEN
    MoveDown        := FALSE;
    MoveUp          := FALSE;
    MoveLeft        := FALSE;
    MoveRight       := FALSE;
    ActivateGrip    := FALSE;
    ActivateRelease := FALSE;
    stepNumber      := 0;
    actionInProgress := FALSE;
ELSE
    // Manual mode control
    IF ManualMode THEN
        MoveDown        := DownButton AND NOT DownLimitSwitch;
        MoveUp          := UpButton AND NOT UpLimitSwitch;
        MoveLeft        := LeftButton AND NOT LeftLimitSwitch;
        MoveRight       := RightButton AND NOT RightLimitSwitch;
        ActivateGrip    := GripButton AND NOT GripLimitSwitch;
        ActivateRelease := ReleaseButton AND NOT ReleaseLimitSwitch;
        stepNumber      := 0;
        actionInProgress := FALSE;
    
    // Single step mode: Start button advances through steps
    ELSIF SingleStepMode THEN
        IF startRisingEdge AND NOT actionInProgress THEN
            stepNumber := stepNumber + 1;
        END_IF;
        
        CASE stepNumber OF
            1:
                MoveDown := TRUE;
                actionInProgress := TRUE;
                IF DownLimitSwitch THEN
                    MoveDown := FALSE;
                    actionInProgress := FALSE;
                END_IF;
            2:
                ActivateGrip := TRUE;
                actionInProgress := TRUE;
                IF GripLimitSwitch THEN
                    ActivateGrip := FALSE;
                    actionInProgress := FALSE;
                END_IF;
            3:
                MoveUp := TRUE;
                actionInProgress := TRUE;
                IF UpLimitSwitch THEN
                    MoveUp := FALSE;
                    actionInProgress := FALSE;
                END_IF;
            4:
                MoveRight := TRUE;
                actionInProgress := TRUE;
                IF RightLimitSwitch THEN
                    MoveRight := FALSE;
                    actionInProgress := FALSE;
                END_IF;
            5:
                MoveDown := TRUE;
                actionInProgress := TRUE;
                IF DownLimitSwitch THEN
                    MoveDown := FALSE;
                    actionInProgress := FALSE;
                END_IF;
            6:
                ActivateRelease := TRUE;
                actionInProgress := TRUE;
                IF ReleaseLimitSwitch THEN
                    ActivateRelease := FALSE;
                    actionInProgress := FALSE;
                END_IF;
            7:
                MoveUp := TRUE;
                actionInProgress := TRUE;
                IF UpLimitSwitch THEN
                    MoveUp := FALSE;
                    actionInProgress := FALSE;
                END_IF;
            8:
                MoveLeft := TRUE;
                actionInProgress := TRUE;
                IF LeftLimitSwitch THEN
                    MoveLeft := FALSE;
                    actionInProgress := FALSE;
                END_IF;
        END_CASE;
        
        IF stepNumber > 8 THEN
            stepNumber := 0;
        END_IF;
    
    // Single cycle mode: executes full cycle once then stops
    ELSIF SingleCycleMode THEN
        IF startRisingEdge THEN
            stepNumber := 1;
            actionInProgress := FALSE;
        END_IF;
        
        CASE stepNumber OF
            1:
                MoveDown := TRUE;
                actionInProgress := TRUE;
                IF DownLimitSwitch THEN
                    MoveDown := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 2;
                END_IF;
            2:
                ActivateGrip := TRUE;
                actionInProgress := TRUE;
                IF GripLimitSwitch THEN
                    ActivateGrip := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 3;
                END_IF;
            3:
                MoveUp := TRUE;
                actionInProgress := TRUE;
                IF UpLimitSwitch THEN
                    MoveUp := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 4;
                END_IF;
            4:
                MoveRight := TRUE;
                actionInProgress := TRUE;
                IF RightLimitSwitch THEN
                    MoveRight := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 5;
                END_IF;
            5:
                MoveDown := TRUE;
                actionInProgress := TRUE;
                IF DownLimitSwitch THEN
                    MoveDown := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 6;
                END_IF;
            6:
                ActivateRelease := TRUE;
                actionInProgress := TRUE;
                IF ReleaseLimitSwitch THEN
                    ActivateRelease := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 7;
                END_IF;
            7:
                MoveUp := TRUE;
                actionInProgress := TRUE;
                IF UpLimitSwitch THEN
                    MoveUp := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 8;
                END_IF;
            8:
                MoveLeft := TRUE;
                actionInProgress := TRUE;
                IF LeftLimitSwitch THEN
                    MoveLeft := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 0;
                END_IF;
        END_CASE;
    
    // Continuous mode: executes full cycle repeatedly
    ELSIF ContinuousMode THEN
        IF startRisingEdge THEN
            stepNumber := 1;
            actionInProgress := FALSE;
        END_IF;
        
        CASE stepNumber OF
            1:
                MoveDown := TRUE;
                actionInProgress := TRUE;
                IF DownLimitSwitch THEN
                    MoveDown := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 2;
                END_IF;
            2:
                ActivateGrip := TRUE;
                actionInProgress := TRUE;
                IF GripLimitSwitch THEN
                    ActivateGrip := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 3;
                END_IF;
            3:
                MoveUp := TRUE;
                actionInProgress := TRUE;
                IF UpLimitSwitch THEN
                    MoveUp := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 4;
                END_IF;
            4:
                MoveRight := TRUE;
                actionInProgress := TRUE;
                IF RightLimitSwitch THEN
                    MoveRight := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 5;
                END_IF;
            5:
                MoveDown := TRUE;
                actionInProgress := TRUE;
                IF DownLimitSwitch THEN
                    MoveDown := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 6;
                END_IF;
            6:
                ActivateRelease := TRUE;
                actionInProgress := TRUE;
                IF ReleaseLimitSwitch THEN
                    ActivateRelease := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 7;
                END_IF;
            7:
                MoveUp := TRUE;
                actionInProgress := TRUE;
                IF UpLimitSwitch THEN
                    MoveUp := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 8;
                END_IF;
            8:
                MoveLeft := TRUE;
                actionInProgress := TRUE;
                IF LeftLimitSwitch THEN
                    MoveLeft := FALSE;
                    actionInProgress := FALSE;
                    stepNumber := 1;
                END_IF;
        END_CASE;
    END_IF;
END_IF;
END_FUNCTION_BLOCK