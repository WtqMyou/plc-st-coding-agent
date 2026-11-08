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
    StartPrev : BOOL;
    StartPulse : BOOL;
    ModeId : INT;
    PrevModeId : INT;
    Step : INT := 0;
    StepDone : BOOL;
    WDown : BOOL;
    WUp : BOOL;
    WLeft : BOOL;
    WRight : BOOL;
    WGrip : BOOL;
    WRelease : BOOL;
    AutoDown : BOOL;
    AutoUp : BOOL;
    AutoLeft : BOOL;
    AutoRight : BOOL;
    AutoGrip : BOOL;
    AutoRelease : BOOL;
END_VAR

StartPulse := Start AND NOT StartPrev;
StartPrev := Start;

IF ManualMode THEN
    ModeId := 1;
ELSIF SingleStepMode THEN
    ModeId := 2;
ELSIF SingleCycleMode THEN
    ModeId := 3;
ELSIF ContinuousMode THEN
    ModeId := 4;
ELSE
    ModeId := 0;
END_IF

IF ModeId <> PrevModeId THEN
    Step := 0;
END_IF
PrevModeId := ModeId;

StepDone := FALSE;
CASE Step OF
    1: StepDone := DownLimitSwitch;
    2: StepDone := GripLimitSwitch;
    3: StepDone := UpLimitSwitch;
    4: StepDone := RightLimitSwitch;
    5: StepDone := DownLimitSwitch;
    6: StepDone := ReleaseLimitSwitch;
    7: StepDone := UpLimitSwitch;
    8: StepDone := LeftLimitSwitch;
END_CASE

IF EmergencyStop THEN
    IF ModeId = 2 THEN
        IF StartPulse THEN
            IF Step = 0 THEN
                Step := 1;
            ELSIF StepDone THEN
                IF Step = 8 THEN
                    Step := 1;
                ELSE
                    Step := Step + 1;
                END_IF
            END_IF
        END_IF
    ELSIF ModeId = 3 THEN
        IF StartPulse AND (Step = 0) THEN
            Step := 1;
        ELSIF (Step > 0) AND StepDone THEN
            IF Step = 8 THEN
                Step := 0;
            ELSE
                Step := Step + 1;
            END_IF
        END_IF
    ELSIF ModeId = 4 THEN
        IF StartPulse AND (Step = 0) THEN
            Step := 1;
        ELSIF (Step > 0) AND StepDone THEN
            IF Step = 8 THEN
                Step := 1;
            ELSE
                Step := Step + 1;
            END_IF
        END_IF
    END_IF
END_IF

AutoDown := FALSE;
AutoUp := FALSE;
AutoLeft := FALSE;
AutoRight := FALSE;
AutoGrip := FALSE;
AutoRelease := FALSE;

CASE Step OF
    1: AutoDown := NOT DownLimitSwitch;
    2: AutoGrip := NOT GripLimitSwitch;
    3: AutoUp := NOT UpLimitSwitch;
    4: AutoRight := NOT RightLimitSwitch;
    5: AutoDown := NOT DownLimitSwitch;
    6: AutoRelease := NOT ReleaseLimitSwitch;
    7: AutoUp := NOT UpLimitSwitch;
    8: AutoLeft := NOT LeftLimitSwitch;
END_CASE

IF EmergencyStop THEN
    IF ModeId = 1 THEN
        WDown := DownButton AND NOT DownLimitSwitch;
        WUp := UpButton AND NOT UpLimitSwitch AND NOT WDown;
        WLeft := LeftButton AND NOT LeftLimitSwitch;
        WRight := RightButton AND NOT RightLimitSwitch AND NOT WLeft;
        WGrip := GripButton AND NOT GripLimitSwitch;
        WRelease := ReleaseButton AND NOT ReleaseLimitSwitch AND NOT WGrip;
    ELSIF (ModeId = 2) OR (ModeId = 3) OR (ModeId = 4) THEN
        WDown := AutoDown;
        WUp := AutoUp;
        WLeft := AutoLeft;
        WRight := AutoRight;
        WGrip := AutoGrip;
        WRelease := AutoRelease;
    ELSE
        WDown := FALSE;
        WUp := FALSE;
        WLeft := FALSE;
        WRight := FALSE;
        WGrip := FALSE;
        WRelease := FALSE;
    END_IF
ELSE
    WDown := FALSE;
    WUp := FALSE;
    WLeft := FALSE;
    WRight := FALSE;
    WGrip := FALSE;
    WRelease := FALSE;
END_IF

MoveDown := WDown;
MoveUp := WUp;
MoveLeft := WLeft;
MoveRight := WRight;
ActivateGrip := WGrip;
ActivateRelease := WRelease;
END_FUNCTION_BLOCK