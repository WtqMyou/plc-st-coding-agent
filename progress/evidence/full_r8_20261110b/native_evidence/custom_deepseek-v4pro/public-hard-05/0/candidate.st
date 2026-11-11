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
    step : INT := 1;
    busy : BOOL := FALSE;
    prevStart : BOOL := FALSE;
    prevAutoSelected : BOOL := FALSE;
    startRising : BOOL;
    autoSelected : BOOL;
    stepDone : BOOL;
END_VAR

autoSelected := NOT ManualMode AND (SingleStepMode OR SingleCycleMode OR ContinuousMode);

IF autoSelected AND NOT prevAutoSelected THEN
    step := 1;
    busy := FALSE;
END_IF;
prevAutoSelected := autoSelected;

startRising := Start AND NOT prevStart;
prevStart := Start;

IF autoSelected AND EmergencyStop THEN
    IF startRising THEN
        IF NOT busy THEN
            busy := TRUE;
        END_IF;
    END_IF;
    
    IF busy THEN
        stepDone := FALSE;
        CASE step OF
            1: stepDone := DownLimitSwitch;
            2: stepDone := GripLimitSwitch;
            3: stepDone := UpLimitSwitch;
            4: stepDone := RightLimitSwitch;
            5: stepDone := DownLimitSwitch;
            6: stepDone := ReleaseLimitSwitch;
            7: stepDone := UpLimitSwitch;
            8: stepDone := LeftLimitSwitch;
        END_CASE;
        
        IF stepDone THEN
            IF SingleStepMode THEN
                busy := FALSE;
                step := step MOD 8 + 1;
            ELSIF SingleCycleMode THEN
                IF step = 8 THEN
                    busy := FALSE;
                    step := 1;
                ELSE
                    step := step + 1;
                END_IF;
            ELSIF ContinuousMode THEN
                step := step MOD 8 + 1;
            END_IF;
        END_IF;
    END_IF;
END_IF;

IF EmergencyStop THEN
    IF ManualMode THEN
        MoveDown := DownButton AND NOT UpButton AND NOT DownLimitSwitch;
        MoveUp := UpButton AND NOT DownButton AND NOT UpLimitSwitch;
        MoveLeft := LeftButton AND NOT RightButton AND NOT LeftLimitSwitch;
        MoveRight := RightButton AND NOT LeftButton AND NOT RightLimitSwitch;
        ActivateGrip := GripButton AND NOT ReleaseButton AND NOT GripLimitSwitch;
        ActivateRelease := ReleaseButton AND NOT GripButton AND NOT ReleaseLimitSwitch;
    ELSIF autoSelected THEN
        IF busy THEN
            MoveDown := ((step = 1) OR (step = 5)) AND NOT DownLimitSwitch;
            MoveUp := ((step = 3) OR (step = 7)) AND NOT UpLimitSwitch;
            MoveLeft := (step = 8) AND NOT LeftLimitSwitch;
            MoveRight := (step = 4) AND NOT RightLimitSwitch;
            ActivateGrip := (step = 2) AND NOT GripLimitSwitch;
            ActivateRelease := (step = 6) AND NOT ReleaseLimitSwitch;
        ELSE
            MoveDown := FALSE;
            MoveUp := FALSE;
            MoveLeft := FALSE;
            MoveRight := FALSE;
            ActivateGrip := FALSE;
            ActivateRelease := FALSE;
        END_IF;
    ELSE
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;
    END_IF;
ELSE
    MoveDown := FALSE;
    MoveUp := FALSE;
    MoveLeft := FALSE;
    MoveRight := FALSE;
    ActivateGrip := FALSE;
    ActivateRelease := FALSE;
END_IF;

END_FUNCTION_BLOCK