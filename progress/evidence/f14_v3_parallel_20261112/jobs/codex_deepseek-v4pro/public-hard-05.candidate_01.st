FUNCTION_BLOCK MechanicalArmControl
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
    prevStart : BOOL;
    startEdge : BOOL;
    currentStep : INT := 0;
    cycleRunning : BOOL := FALSE;
    stepComplete : BOOL;
    prevManual : BOOL;
    prevSingleStep : BOOL;
    prevSingleCycle : BOOL;
    prevContinuous : BOOL;
END_VAR

startEdge := Start AND NOT prevStart AND EmergencyStop;

MoveDown := FALSE;
MoveUp := FALSE;
MoveLeft := FALSE;
MoveRight := FALSE;
ActivateGrip := FALSE;
ActivateRelease := FALSE;

IF ManualMode THEN
    IF NOT prevManual THEN
        currentStep := 0;
        cycleRunning := FALSE;
    END_IF;

    IF DownButton AND NOT DownLimitSwitch THEN
        MoveDown := TRUE;
    END_IF;
    IF UpButton AND NOT UpLimitSwitch THEN
        MoveUp := TRUE;
    END_IF;
    IF LeftButton AND NOT LeftLimitSwitch THEN
        MoveLeft := TRUE;
    END_IF;
    IF RightButton AND NOT RightLimitSwitch THEN
        MoveRight := TRUE;
    END_IF;
    IF GripButton AND NOT GripLimitSwitch THEN
        ActivateGrip := TRUE;
    END_IF;
    IF ReleaseButton AND NOT ReleaseLimitSwitch THEN
        ActivateRelease := TRUE;
    END_IF;

ELSIF SingleStepMode THEN
    IF NOT prevSingleStep THEN
        currentStep := 0;
    END_IF;

    IF startEdge THEN
        IF currentStep = 0 THEN
            currentStep := 1;
        ELSIF currentStep = 1 AND DownLimitSwitch THEN
            currentStep := 2;
        ELSIF currentStep = 2 AND GripLimitSwitch THEN
            currentStep := 3;
        ELSIF currentStep = 3 AND UpLimitSwitch THEN
            currentStep := 4;
        ELSIF currentStep = 4 AND RightLimitSwitch THEN
            currentStep := 5;
        ELSIF currentStep = 5 AND DownLimitSwitch THEN
            currentStep := 6;
        ELSIF currentStep = 6 AND ReleaseLimitSwitch THEN
            currentStep := 7;
        ELSIF currentStep = 7 AND UpLimitSwitch THEN
            currentStep := 8;
        ELSIF currentStep = 8 AND LeftLimitSwitch THEN
            currentStep := 1;
        END_IF;
    END_IF;

    CASE currentStep OF
        1:
            MoveDown := NOT DownLimitSwitch;
        2:
            ActivateGrip := NOT GripLimitSwitch;
        3:
            MoveUp := NOT UpLimitSwitch;
        4:
            MoveRight := NOT RightLimitSwitch;
        5:
            MoveDown := NOT DownLimitSwitch;
        6:
            ActivateRelease := NOT ReleaseLimitSwitch;
        7:
            MoveUp := NOT UpLimitSwitch;
        8:
            MoveLeft := NOT LeftLimitSwitch;
    END_CASE;

ELSIF SingleCycleMode OR ContinuousMode THEN
    IF (SingleCycleMode AND NOT prevSingleCycle) OR (ContinuousMode AND NOT prevContinuous) THEN
        currentStep := 0;
        cycleRunning := FALSE;
    END_IF;

    IF startEdge AND NOT cycleRunning THEN
        cycleRunning := TRUE;
        currentStep := 1;
    END_IF;

    IF cycleRunning AND EmergencyStop THEN
        stepComplete := FALSE;

        CASE currentStep OF
            1:
                MoveDown := NOT DownLimitSwitch;
                stepComplete := DownLimitSwitch;
            2:
                ActivateGrip := NOT GripLimitSwitch;
                stepComplete := GripLimitSwitch;
            3:
                MoveUp := NOT UpLimitSwitch;
                stepComplete := UpLimitSwitch;
            4:
                MoveRight := NOT RightLimitSwitch;
                stepComplete := RightLimitSwitch;
            5:
                MoveDown := NOT DownLimitSwitch;
                stepComplete := DownLimitSwitch;
            6:
                ActivateRelease := NOT ReleaseLimitSwitch;
                stepComplete := ReleaseLimitSwitch;
            7:
                MoveUp := NOT UpLimitSwitch;
                stepComplete := UpLimitSwitch;
            8:
                MoveLeft := NOT LeftLimitSwitch;
                stepComplete := LeftLimitSwitch;
        END_CASE;

        IF stepComplete THEN
            IF currentStep < 8 THEN
                currentStep := currentStep + 1;
            ELSIF SingleCycleMode THEN
                cycleRunning := FALSE;
                currentStep := 0;
            ELSE
                currentStep := 1;
            END_IF;
        END_IF;
    END_IF;
END_IF;

prevStart := Start;
prevManual := ManualMode;
prevSingleStep := SingleStepMode;
prevSingleCycle := SingleCycleMode;
prevContinuous := ContinuousMode;

IF NOT EmergencyStop THEN
    MoveDown := FALSE;
    MoveUp := FALSE;
    MoveLeft := FALSE;
    MoveRight := FALSE;
    ActivateGrip := FALSE;
    ActivateRelease := FALSE;
END_IF;

END_FUNCTION_BLOCK