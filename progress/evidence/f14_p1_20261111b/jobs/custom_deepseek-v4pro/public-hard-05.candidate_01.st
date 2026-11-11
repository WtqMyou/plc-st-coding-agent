PROGRAM MechanicalArmControl
VAR_INPUT
    ManualMode: BOOL;
    SingleStepMode: BOOL;
    SingleCycleMode: BOOL;
    ContinuousMode: BOOL;
    EmergencyStop: BOOL;
    Start: BOOL;
    DownButton: BOOL;
    UpButton: BOOL;
    LeftButton: BOOL;
    RightButton: BOOL;
    GripButton: BOOL;
    ReleaseButton: BOOL;
    DownLimitSwitch: BOOL;
    UpLimitSwitch: BOOL;
    LeftLimitSwitch: BOOL;
    RightLimitSwitch: BOOL;
    GripLimitSwitch: BOOL;
    ReleaseLimitSwitch: BOOL;
END_VAR
VAR_OUTPUT
    MoveDown: BOOL;
    MoveUp: BOOL;
    MoveLeft: BOOL;
    MoveRight: BOOL;
    ActivateGrip: BOOL;
    ActivateRelease: BOOL;
END_VAR
VAR
    prevStart: BOOL := FALSE;
    startRising: BOOL;
    stepIndex: INT := 0;
    executing: BOOL := FALSE;
END_VAR

// Rising edge detection for Start button
startRising := Start AND NOT prevStart;
prevStart := Start;

IF NOT EmergencyStop THEN
    // Emergency stop active: stop all actions and reset automatic state
    executing := FALSE;
    stepIndex := 0;
ELSE
    // Normal operation
    IF ManualMode THEN
        // Manual mode: no automatic state; reset if switching from auto
        executing := FALSE;
        stepIndex := 0;
    ELSIF SingleStepMode THEN
        // Single step mode: one action per Start press
        IF startRising AND NOT executing THEN
            executing := TRUE;
        END_IF;
        IF executing THEN
            CASE stepIndex OF
                0: IF DownLimitSwitch THEN executing := FALSE; stepIndex := 1; END_IF
                1: IF GripLimitSwitch THEN executing := FALSE; stepIndex := 2; END_IF
                2: IF UpLimitSwitch THEN executing := FALSE; stepIndex := 3; END_IF
                3: IF RightLimitSwitch THEN executing := FALSE; stepIndex := 4; END_IF
                4: IF DownLimitSwitch THEN executing := FALSE; stepIndex := 5; END_IF
                5: IF ReleaseLimitSwitch THEN executing := FALSE; stepIndex := 6; END_IF
                6: IF UpLimitSwitch THEN executing := FALSE; stepIndex := 7; END_IF
                7: IF LeftLimitSwitch THEN executing := FALSE; stepIndex := 0; END_IF
            END_CASE;
        END_IF;
    ELSIF SingleCycleMode THEN
        // Single cycle mode: full cycle once per Start press
        IF startRising AND NOT executing THEN
            executing := TRUE;
            stepIndex := 0;
        END_IF;
        IF executing THEN
            CASE stepIndex OF
                0: IF DownLimitSwitch THEN stepIndex := 1; END_IF
                1: IF GripLimitSwitch THEN stepIndex := 2; END_IF
                2: IF UpLimitSwitch THEN stepIndex := 3; END_IF
                3: IF RightLimitSwitch THEN stepIndex := 4; END_IF
                4: IF DownLimitSwitch THEN stepIndex := 5; END_IF
                5: IF ReleaseLimitSwitch THEN stepIndex := 6; END_IF
                6: IF UpLimitSwitch THEN stepIndex := 7; END_IF
                7: IF LeftLimitSwitch THEN
                        executing := FALSE;
                        stepIndex := 0;
                    END_IF
            END_CASE;
        END_IF;
    ELSIF ContinuousMode THEN
        // Continuous mode: repeat cycles until stopped
        IF startRising AND NOT executing THEN
            executing := TRUE;
            stepIndex := 0;
        END_IF;
        IF executing THEN
            CASE stepIndex OF
                0: IF DownLimitSwitch THEN stepIndex := 1; END_IF
                1: IF GripLimitSwitch THEN stepIndex := 2; END_IF
                2: IF UpLimitSwitch THEN stepIndex := 3; END_IF
                3: IF RightLimitSwitch THEN stepIndex := 4; END_IF
                4: IF DownLimitSwitch THEN stepIndex := 5; END_IF
                5: IF ReleaseLimitSwitch THEN stepIndex := 6; END_IF
                6: IF UpLimitSwitch THEN stepIndex := 7; END_IF
                7: IF LeftLimitSwitch THEN stepIndex := 0; END_IF
            END_CASE;
        END_IF;
    ELSE
        // No valid mode selected
        executing := FALSE;
        stepIndex := 0;
    END_IF;
END_IF;

// Output assignment
MoveDown := FALSE;
MoveUp := FALSE;
MoveLeft := FALSE;
MoveRight := FALSE;
ActivateGrip := FALSE;
ActivateRelease := FALSE;

IF EmergencyStop THEN
    IF ManualMode THEN
        MoveDown := DownButton AND NOT DownLimitSwitch;
        MoveUp := UpButton AND NOT UpLimitSwitch;
        MoveLeft := LeftButton AND NOT LeftLimitSwitch;
        MoveRight := RightButton AND NOT RightLimitSwitch;
        ActivateGrip := GripButton AND NOT GripLimitSwitch;
        ActivateRelease := ReleaseButton AND NOT ReleaseLimitSwitch;
    ELSIF SingleStepMode OR SingleCycleMode OR ContinuousMode THEN
        IF executing THEN
            CASE stepIndex OF
                0: MoveDown := NOT DownLimitSwitch;
                1: ActivateGrip := NOT GripLimitSwitch;
                2: MoveUp := NOT UpLimitSwitch;
                3: MoveRight := NOT RightLimitSwitch;
                4: MoveDown := NOT DownLimitSwitch;
                5: ActivateRelease := NOT ReleaseLimitSwitch;
                6: MoveUp := NOT UpLimitSwitch;
                7: MoveLeft := NOT LeftLimitSwitch;
            END_CASE;
        END_IF;
    END_IF;
END_IF;