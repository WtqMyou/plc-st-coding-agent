FUNCTION_BLOCK MechanicalArmControl
VAR_INPUT
    ManualMode       : BOOL;
    SingleStepMode   : BOOL;
    SingleCycleMode  : BOOL;
    ContinuousMode   : BOOL;
    EmergencyStop    : BOOL;
    Start            : BOOL;
    DownButton       : BOOL;
    UpButton         : BOOL;
    LeftButton       : BOOL;
    RightButton      : BOOL;
    GripButton       : BOOL;
    ReleaseButton    : BOOL;
    DownLimitSwitch  : BOOL;
    UpLimitSwitch    : BOOL;
    LeftLimitSwitch  : BOOL;
    RightLimitSwitch : BOOL;
    GripLimitSwitch  : BOOL;
    ReleaseLimitSwitch : BOOL;
END_VAR

VAR_OUTPUT
    MoveDown       : BOOL;
    MoveUp         : BOOL;
    MoveLeft       : BOOL;
    MoveRight      : BOOL;
    ActivateGrip   : BOOL;
    ActivateRelease : BOOL;
END_VAR

VAR
    step         : UINT;
    prevStart    : BOOL;
    startPressed : BOOL;
    cycleActive  : BOOL;
END_VAR

// Reset all outputs first
MoveDown := FALSE;
MoveUp := FALSE;
MoveLeft := FALSE;
MoveRight := FALSE;
ActivateGrip := FALSE;
ActivateRelease := FALSE;

// Emergency stop: immediate halt
IF NOT EmergencyStop THEN
    step := 0;
    cycleActive := FALSE;
    prevStart := FALSE;
    RETURN;
END_IF;

// Rising edge detection for Start
startPressed := Start AND NOT prevStart;
prevStart := Start;

// Manual mode: Direct control via buttons
IF ManualMode THEN
    MoveDown := DownButton AND NOT DownLimitSwitch;
    MoveUp := UpButton AND NOT UpLimitSwitch;
    MoveLeft := LeftButton AND NOT LeftLimitSwitch;
    MoveRight := RightButton AND NOT RightLimitSwitch;
    ActivateGrip := GripButton;
    ActivateRelease := ReleaseButton;
    step := 0;
    cycleActive := FALSE;

// Single step mode: One action per Start press
ELSIF SingleStepMode THEN
    IF startPressed THEN
        step := step + 1;
        IF step > 8 THEN
            step := 1;
        END_IF;
    END_IF;
    
    // Execute current step
    CASE step OF
        1: MoveDown := NOT DownLimitSwitch;
        2: ActivateGrip := NOT GripLimitSwitch;
        3: MoveUp := NOT UpLimitSwitch;
        4: MoveRight := NOT RightLimitSwitch;
        5: MoveDown := NOT DownLimitSwitch;
        6: ActivateRelease := NOT ReleaseLimitSwitch;
        7: MoveUp := NOT UpLimitSwitch;
        8: MoveLeft := NOT LeftLimitSwitch;
    END_CASE;
    
    // Check completion and reset to wait for next Start
    CASE step OF
        1: IF DownLimitSwitch THEN step := 0; END_IF;
        2: IF GripLimitSwitch THEN step := 0; END_IF;
        3: IF UpLimitSwitch THEN step := 0; END_IF;
        4: IF RightLimitSwitch THEN step := 0; END_IF;
        5: IF DownLimitSwitch THEN step := 0; END_IF;
        6: IF ReleaseLimitSwitch THEN step := 0; END_IF;
        7: IF UpLimitSwitch THEN step := 0; END_IF;
        8: IF LeftLimitSwitch THEN step := 0; END_IF;
    END_CASE;

// Single cycle mode: Full sequence automatic, stop at end
ELSIF SingleCycleMode THEN
    IF startPressed THEN
        step := 0;
        cycleActive := TRUE;
    END_IF;
    
    IF cycleActive THEN
        CASE step OF
            0: MoveDown := NOT DownLimitSwitch;
            1: ActivateGrip := NOT GripLimitSwitch;
            2: MoveUp := NOT UpLimitSwitch;
            3: MoveRight := NOT RightLimitSwitch;
            4: MoveDown := NOT DownLimitSwitch;
            5: ActivateRelease := NOT ReleaseLimitSwitch;
            6: MoveUp := NOT UpLimitSwitch;
            7: MoveLeft := NOT LeftLimitSwitch;
        END_CASE;
        
        CASE step OF
            0: IF DownLimitSwitch THEN step := 1; END_IF;
            1: IF GripLimitSwitch THEN step := 2; END_IF;
            2: IF UpLimitSwitch THEN step := 3; END_IF;
            3: IF RightLimitSwitch THEN step := 4; END_IF;
            4: IF DownLimitSwitch THEN step := 5; END_IF;
            5: IF ReleaseLimitSwitch THEN step := 6; END_IF;
            6: IF UpLimitSwitch THEN step := 7; END_IF;
            7: IF LeftLimitSwitch THEN
                   step := 0;
                   cycleActive := FALSE;
               END_IF;
        END_CASE;
    END_IF;

// Continuous mode: Full sequence repeating
ELSIF ContinuousMode THEN
    IF startPressed THEN
        step := 0;
        cycleActive := TRUE;
    END_IF;
    
    IF cycleActive THEN
        CASE step OF
            0: MoveDown := NOT DownLimitSwitch;
            1: ActivateGrip := NOT GripLimitSwitch;
            2: MoveUp := NOT UpLimitSwitch;
            3: MoveRight := NOT RightLimitSwitch;
            4: MoveDown := NOT DownLimitSwitch;
            5: ActivateRelease := NOT ReleaseLimitSwitch;
            6: MoveUp := NOT UpLimitSwitch;
            7: MoveLeft := NOT LeftLimitSwitch;
        END_CASE;
        
        CASE step OF
            0: IF DownLimitSwitch THEN step := 1; END_IF;
            1: IF GripLimitSwitch THEN step := 2; END_IF;
            2: IF UpLimitSwitch THEN step := 3; END_IF;
            3: IF RightLimitSwitch THEN step := 4; END_IF;
            4: IF DownLimitSwitch THEN step := 5; END_IF;
            5: IF ReleaseLimitSwitch THEN step := 6; END_IF;
            6: IF UpLimitSwitch THEN step := 7; END_IF;
            7: IF LeftLimitSwitch THEN step := 0; END_IF;
        END_CASE;
    END_IF;

END_IF;
END_FUNCTION_BLOCK