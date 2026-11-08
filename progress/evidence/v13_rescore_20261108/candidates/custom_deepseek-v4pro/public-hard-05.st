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
    StartRise : BOOL;
    StartPrev : BOOL;
    AutoModeActive : BOOL;
    PrevAutoModeActive : BOOL;
    StepIndex : INT := 1;
    WaitingForStart : BOOL := TRUE;
    ManMoveDown : BOOL;
    ManMoveUp : BOOL;
    ManMoveLeft : BOOL;
    ManMoveRight : BOOL;
    ManGrip : BOOL;
    ManRelease : BOOL;
    AutoMoveDown : BOOL;
    AutoMoveUp : BOOL;
    AutoMoveLeft : BOOL;
    AutoMoveRight : BOOL;
    AutoGrip : BOOL;
    AutoRelease : BOOL;
    ReqMoveDown : BOOL;
    ReqMoveUp : BOOL;
    ReqMoveLeft : BOOL;
    ReqMoveRight : BOOL;
    ReqGrip : BOOL;
    ReqRelease : BOOL;
    StepDone : BOOL;
END_VAR

StartRise := Start AND NOT StartPrev;
StartPrev := Start;

AutoModeActive := SingleStepMode OR SingleCycleMode OR ContinuousMode;

IF AutoModeActive AND NOT PrevAutoModeActive THEN
    StepIndex := 1;
    WaitingForStart := TRUE;
END_IF;
PrevAutoModeActive := AutoModeActive;

ManMoveDown := ManualMode AND DownButton AND NOT DownLimitSwitch;
ManMoveUp := ManualMode AND UpButton AND NOT UpLimitSwitch;
ManMoveLeft := ManualMode AND LeftButton AND NOT LeftLimitSwitch;
ManMoveRight := ManualMode AND RightButton AND NOT RightLimitSwitch;
ManGrip := ManualMode AND GripButton AND NOT GripLimitSwitch;
ManRelease := ManualMode AND ReleaseButton AND NOT ReleaseLimitSwitch;

IF EmergencyStop THEN
    IF AutoModeActive THEN
        IF WaitingForStart THEN
            IF StartRise THEN
                WaitingForStart := FALSE;
            END_IF;
        ELSE
            StepDone := FALSE;
            CASE StepIndex OF
                1: StepDone := DownLimitSwitch;
                2: StepDone := GripLimitSwitch;
                3: StepDone := UpLimitSwitch;
                4: StepDone := RightLimitSwitch;
                5: StepDone := DownLimitSwitch;
                6: StepDone := ReleaseLimitSwitch;
                7: StepDone := UpLimitSwitch;
                8: StepDone := LeftLimitSwitch;
            END_CASE;
            IF StepDone THEN
                IF SingleStepMode THEN
                    WaitingForStart := TRUE;
                    IF StepIndex >= 8 THEN
                        StepIndex := 1;
                    ELSE
                        StepIndex := StepIndex + 1;
                    END_IF;
                ELSIF SingleCycleMode THEN
                    IF StepIndex >= 8 THEN
                        StepIndex := 1;
                        WaitingForStart := TRUE;
                    ELSE
                        StepIndex := StepIndex + 1;
                    END_IF;
                ELSIF ContinuousMode THEN
                    IF StepIndex >= 8 THEN
                        StepIndex := 1;
                    ELSE
                        StepIndex := StepIndex + 1;
                    END_IF;
                END_IF;
            END_IF;
        END_IF;
    END_IF;
END_IF;

IF AutoModeActive AND NOT WaitingForStart THEN
    AutoMoveDown := (StepIndex = 1) OR (StepIndex = 5);
    AutoMoveUp := (StepIndex = 3) OR (StepIndex = 7);
    AutoMoveLeft := (StepIndex = 8);
    AutoMoveRight := (StepIndex = 4);
    AutoGrip := (StepIndex = 2);
    AutoRelease := (StepIndex = 6);
ELSE
    AutoMoveDown := FALSE;
    AutoMoveUp := FALSE;
    AutoMoveLeft := FALSE;
    AutoMoveRight := FALSE;
    AutoGrip := FALSE;
    AutoRelease := FALSE;
END_IF;

ReqMoveDown := ManMoveDown OR AutoMoveDown;
ReqMoveUp := ManMoveUp OR AutoMoveUp;
ReqMoveLeft := ManMoveLeft OR AutoMoveLeft;
ReqMoveRight := ManMoveRight OR AutoMoveRight;
ReqGrip := ManGrip OR AutoGrip;
ReqRelease := ManRelease OR AutoRelease;

MoveDown := ReqMoveDown AND NOT ReqMoveUp;
MoveUp := ReqMoveUp AND NOT ReqMoveDown;
MoveLeft := ReqMoveLeft AND NOT ReqMoveRight;
MoveRight := ReqMoveRight AND NOT ReqMoveLeft;
ActivateGrip := ReqGrip AND NOT ReqRelease;
ActivateRelease := ReqRelease AND NOT ReqGrip;

IF NOT EmergencyStop THEN
    MoveDown := FALSE;
    MoveUp := FALSE;
    MoveLeft := FALSE;
    MoveRight := FALSE;
    ActivateGrip := FALSE;
    ActivateRelease := FALSE;
END_IF;

END_FUNCTION_BLOCK