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
    step        : UINT;
    prevStart   : BOOL;
    startPressed : BOOL;
    prevStep    : UINT;
    cycleActive : BOOL;
END_VAR

// Emergency stop handling
IF NOT EmergencyStop THEN
    MoveDown := FALSE;
    MoveUp := FALSE;
    MoveLeft := FALSE;
    MoveRight := FALSE;
    ActivateGrip := FALSE;
    ActivateRelease := FALSE;
    step := 0;
    prevStep := 0;
    cycleActive := FALSE;
    RETURN;
END_IF;

// Detect rising edge of Start
startPressed := Start AND NOT prevStart;
prevStart := Start;

// Manual mode: Direct button control, stop at limit switches
IF ManualMode THEN
    MoveDown := DownButton AND NOT DownLimitSwitch;
    MoveUp := UpButton AND NOT UpLimitSwitch;
    MoveLeft := LeftButton AND NOT LeftLimitSwitch;
    MoveRight := RightButton AND NOT RightLimitSwitch;
    ActivateGrip := GripButton;
    ActivateRelease := ReleaseButton;
    step := 0;
    cycleActive := FALSE;

// Single step mode: One action per Start press, wait for completion
ELSIF SingleStepMode THEN
    IF startPressed THEN
        step := step + 1;
        IF step > 8 THEN
            step := 1;
        END_IF;
        prevStep := step;
    END_IF;
    
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
    
    IF step <> prevStep THEN
        prevStep := step;
    ELSIF step > 0 THEN
        CASE step OF
            1: IF DownLimitSwitch THEN step := 0; prevStep := 0; END_IF;
            2: IF GripLimitSwitch THEN step := 0; prevStep := 0; END_IF;
            3: IF UpLimitSwitch THEN step := 0; prevStep := 0; END_IF;
            4: IF RightLimitSwitch THEN step := 0; prevStep := 0; END_IF;
            5: IF DownLimitSwitch THEN step := 0; prevStep := 0; END_IF;
            6: IF ReleaseLimitSwitch THEN step := 0; prevStep := 0; END_IF;
            7: IF UpLimitSwitch THEN step := 0; prevStep := 0; END_IF;
            8: IF LeftLimitSwitch THEN step := 0; prevStep := 0; END_IF;
        END_CASE;
    END_IF;

// Single cycle mode: Full sequence automatic, stop at end
ELSIF SingleCycleMode THEN
    IF startPressed THEN
        cycleActive := TRUE;
        prevStep := 0;
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
        
        IF step <> prevStep THEN
            prevStep := step;
        ELSIF step < 8 THEN
            CASE step OF
                0: IF DownLimitSwitch THEN step := 1; prevStep := 1; END_IF;
                1: IF GripLimitSwitch THEN step := 2; prevStep := 2; END_IF;
                2: IF UpLimitSwitch THEN step := 3; prevStep := 3; END_IF;
                3: IF RightLimitSwitch THEN step := 4; prevStep := 4; END_IF;
                4: IF DownLimitSwitch THEN step := 5; prevStep := 5; END_IF;
                5: IF ReleaseLimitSwitch THEN step := 6; prevStep := 6; END_IF;
                6: IF UpLimitSwitch THEN step := 7; prevStep := 7; END_IF;
                7: IF LeftLimitSwitch THEN step := 0; prevStep := 0; cycleActive := FALSE; END_IF;
            END_CASE;
        END_IF;
    END_IF;

// Continuous mode: Full sequence repeating
ELSIF ContinuousMode THEN
    IF startPressed THEN
        cycleActive := TRUE;
        prevStep := 0;
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
        
        IF step <> prevStep THEN
            prevStep := step;
        ELSIF step < 8 THEN
            CASE step OF
                0: IF DownLimitSwitch THEN step := 1; prevStep := 1; END_IF;
                1: IF GripLimitSwitch THEN step := 2; prevStep := 2; END_IF;
                2: IF UpLimitSwitch THEN step := 3; prevStep := 3; END_IF;
                3: IF RightLimitSwitch THEN step := 4; prevStep := 4; END_IF;
                4: IF DownLimitSwitch THEN step := 5; prevStep := 5; END_IF;
                5: IF ReleaseLimitSwitch THEN step := 6; prevStep := 6; END_IF;
                6: IF UpLimitSwitch THEN step := 7; prevStep := 7; END_IF;
                7: IF LeftLimitSwitch THEN step := 0; prevStep := 0; END_IF;
            END_CASE;
        END_IF;
    END_IF;

END_IF;
END_FUNCTION_BLOCK