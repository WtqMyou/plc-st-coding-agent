FUNCTION_BLOCK MechanicalArmControl
VAR
    Step: INT := 1;                     // Current action step (1..8)
    ActionActive: BOOL := FALSE;        // TRUE when an automated action is being executed
    WaitingForStart: BOOL := TRUE;      // TRUE in single-step mode when waiting for start press
    CycleRunning: BOOL := FALSE;        // TRUE when a cycle is in progress (single/continuous)
    StartPrev: BOOL := FALSE;           // Previous value of Start input for edge detection
    StartPulse: BOOL := FALSE;          // One-scan pulse on rising edge of Start
    WaitingForStartPrev: BOOL := TRUE;  // Snapshot of WaitingForStart at scan start
    CycleRunningPrev: BOOL := FALSE;    // Snapshot of CycleRunning at scan start
END_VAR

// Rising edge detection for Start
StartPulse := Start AND NOT StartPrev;
StartPrev := Start;

// Capture previous states before any logic changes (to avoid race conditions)
WaitingForStartPrev := WaitingForStart;
CycleRunningPrev := CycleRunning;

IF NOT EmergencyStop THEN
    // Emergency stop triggered: stop all actions and reset automated state
    MoveDown := FALSE;
    MoveUp := FALSE;
    MoveLeft := FALSE;
    MoveRight := FALSE;
    ActivateGrip := FALSE;
    ActivateRelease := FALSE;
    Step := 1;
    ActionActive := FALSE;
    WaitingForStart := TRUE;
    CycleRunning := FALSE;
ELSE
    // Normal operation (no emergency stop)
    IF ManualMode THEN
        // Manual mode: direct button control with limit switch interlock
        MoveDown := DownButton AND NOT DownLimitSwitch;
        MoveUp := UpButton AND NOT UpLimitSwitch;
        MoveLeft := LeftButton AND NOT LeftLimitSwitch;
        MoveRight := RightButton AND NOT RightLimitSwitch;
        ActivateGrip := GripButton AND NOT GripLimitSwitch;
        ActivateRelease := ReleaseButton AND NOT ReleaseLimitSwitch;
        // Reset automated state when in manual mode
        Step := 1;
        ActionActive := FALSE;
        WaitingForStart := TRUE;
        CycleRunning := FALSE;
    ELSIF SingleStepMode THEN
        // Single step mode: one action per start press
        // Default outputs to false
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;

        // Start next action if waiting and start pulse occurs
        IF WaitingForStartPrev AND StartPulse THEN
            WaitingForStart := FALSE;
            ActionActive := TRUE;
            Step := 1;  // Always start from step 1
        END_IF;

        // Check completion of current action
        IF ActionActive THEN
            CASE Step OF
                1: IF DownLimitSwitch THEN
                       ActionActive := FALSE;
                       WaitingForStart := TRUE;
                       Step := 1;
                   END_IF;
                2: IF GripLimitSwitch THEN
                       ActionActive := FALSE;
                       WaitingForStart := TRUE;
                       Step := 2;
                   END_IF;
                3: IF UpLimitSwitch THEN
                       ActionActive := FALSE;
                       WaitingForStart := TRUE;
                       Step := 3;
                   END_IF;
                4: IF RightLimitSwitch THEN
                       ActionActive := FALSE;
                       WaitingForStart := TRUE;
                       Step := 4;
                   END_IF;
                5: IF DownLimitSwitch THEN
                       ActionActive := FALSE;
                       WaitingForStart := TRUE;
                       Step := 5;
                   END_IF;
                6: IF ReleaseLimitSwitch THEN
                       ActionActive := FALSE;
                       WaitingForStart := TRUE;
                       Step := 6;
                   END_IF;
                7: IF UpLimitSwitch THEN
                       ActionActive := FALSE;
                       WaitingForStart := TRUE;
                       Step := 7;
                   END_IF;
                8: IF LeftLimitSwitch THEN
                       ActionActive := FALSE;
                       WaitingForStart := TRUE;
                       Step := 1;  // Reset to step 1 for next cycle
                   END_IF;
            END_CASE;
        END_IF;

        // Set outputs based on current step and action active
        IF ActionActive THEN
            CASE Step OF
                1: MoveDown := TRUE;
                2: ActivateGrip := TRUE;
                3: MoveUp := TRUE;
                4: MoveRight := TRUE;
                5: MoveDown := TRUE;
                6: ActivateRelease := TRUE;
                7: MoveUp := TRUE;
                8: MoveLeft := TRUE;
            END_CASE;
        END_IF;
    ELSIF SingleCycleMode THEN
        // Single cycle mode: complete one full cycle automatically
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;

        // Start cycle on rising edge of Start if not already running
        IF NOT CycleRunningPrev AND StartPulse THEN
            CycleRunning := TRUE;
            Step := 1;
            ActionActive := TRUE;
        END_IF;

        // Execute cycle and advance to next action on completion
        IF CycleRunning AND ActionActive THEN
            CASE Step OF
                1: IF DownLimitSwitch THEN Step := 2; END_IF;
                2: IF GripLimitSwitch THEN Step := 3; END_IF;
                3: IF UpLimitSwitch THEN Step := 4; END_IF;
                4: IF RightLimitSwitch THEN Step := 5; END_IF;
                5: IF DownLimitSwitch THEN Step := 6; END_IF;
                6: IF ReleaseLimitSwitch THEN Step := 7; END_IF;
                7: IF UpLimitSwitch THEN Step := 8; END_IF;
                8: IF LeftLimitSwitch THEN
                       ActionActive := FALSE;   // Cycle finished
                       CycleRunning := FALSE;
                       Step := 1;               // Reset for next start
                   END_IF;
            END_CASE;
        END_IF;

        // Set outputs according to current step
        IF CycleRunning AND ActionActive THEN
            CASE Step OF
                1: MoveDown := TRUE;
                2: ActivateGrip := TRUE;
                3: MoveUp := TRUE;
                4: MoveRight := TRUE;
                5: MoveDown := TRUE;
                6: ActivateRelease := TRUE;
                7: MoveUp := TRUE;
                8: MoveLeft := TRUE;
            END_CASE;
        END_IF;
    ELSIF ContinuousMode THEN
        // Continuous mode: repeat cycle indefinitely
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;

        // Start continuous operation on rising edge of Start if not already running
        IF NOT CycleRunningPrev AND StartPulse THEN
            CycleRunning := TRUE;
            Step := 1;
            ActionActive := TRUE;
        END_IF;

        // Execute cycle and loop back to step 1 after step 8
        IF CycleRunning AND ActionActive THEN
            CASE Step OF
                1: IF DownLimitSwitch THEN Step := 2; END_IF;
                2: IF GripLimitSwitch THEN Step := 3; END_IF;
                3: IF UpLimitSwitch THEN Step := 4; END_IF;
                4: IF RightLimitSwitch THEN Step := 5; END_IF;
                5: IF DownLimitSwitch THEN Step := 6; END_IF;
                6: IF ReleaseLimitSwitch THEN Step := 7; END_IF;
                7: IF UpLimitSwitch THEN Step := 8; END_IF;
                8: IF LeftLimitSwitch THEN Step := 1; END_IF;  // Loop back
            END_CASE;
        END_IF;

        // Set outputs according to current step
        IF CycleRunning AND ActionActive THEN
            CASE Step OF
                1: MoveDown := TRUE;
                2: ActivateGrip := TRUE;
                3: MoveUp := TRUE;
                4: MoveRight := TRUE;
                5: MoveDown := TRUE;
                6: ActivateRelease := TRUE;
                7: MoveUp := TRUE;
                8: MoveLeft := TRUE;
            END_CASE;
        END_IF;
    ELSE
        // No mode selected (should not happen, but safe default)
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;
        Step := 1;
        ActionActive := FALSE;
        WaitingForStart := TRUE;
        CycleRunning := FALSE;
    END_IF;
END_IF;