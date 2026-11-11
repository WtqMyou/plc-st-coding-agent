FUNCTION_BLOCK MechanicalArmControl
VAR_INPUT
    ManualMode        : BOOL;
    SingleStepMode    : BOOL;
    SingleCycleMode   : BOOL;
    ContinuousMode    : BOOL;
    EmergencyStop     : BOOL; (* FALSE: emergency stop triggered; TRUE: normal *)
    Start             : BOOL;
    DownButton        : BOOL;
    UpButton          : BOOL;
    LeftButton        : BOOL;
    RightButton       : BOOL;
    GripButton        : BOOL;
    ReleaseButton     : BOOL;
    DownLimitSwitch   : BOOL;
    UpLimitSwitch     : BOOL;
    LeftLimitSwitch   : BOOL;
    RightLimitSwitch  : BOOL;
    GripLimitSwitch   : BOOL;
    ReleaseLimitSwitch: BOOL;
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
    StartPrev        : BOOL := FALSE;
    StartEdge        : BOOL := FALSE;
    StepActive       : BOOL := FALSE;
    StepIndex        : INT  := 0;
    SingleCycleState : INT  := 0;
    ContinuousState  : INT  := 0;
END_VAR

(* Rising edge of Start *)
StartEdge := Start AND NOT StartPrev;
StartPrev := Start;

(* Clear all commands first; emergency stop therefore disables all outputs. *)
MoveDown        := FALSE;
MoveUp          := FALSE;
MoveLeft        := FALSE;
MoveRight       := FALSE;
ActivateGrip    := FALSE;
ActivateRelease := FALSE;

IF NOT EmergencyStop THEN
    StartEdge := FALSE;

    StepActive       := FALSE;
    StepIndex        := 0;
    SingleCycleState := 0;
    ContinuousState  := 0;
ELSE
    (* ---------- Manual mode ---------- *)
    IF ManualMode THEN
        MoveDown        := DownButton    AND NOT DownLimitSwitch;
        MoveUp          := UpButton      AND NOT UpLimitSwitch;
        MoveLeft        := LeftButton    AND NOT LeftLimitSwitch;
        MoveRight       := RightButton   AND NOT RightLimitSwitch;
        ActivateGrip    := GripButton    AND NOT GripLimitSwitch;
        ActivateRelease := ReleaseButton AND NOT ReleaseLimitSwitch;
    END_IF;

    (* ---------- Single step mode ---------- *)
    IF SingleStepMode THEN
        IF StartEdge THEN
            StepIndex := StepIndex + 1;
            IF StepIndex > 8 THEN
                StepIndex := 1;
            END_IF;
            StepActive := TRUE;
        END_IF;

        IF StepActive THEN
            CASE StepIndex OF
                1: (* Down *)
                    IF DownLimitSwitch THEN
                        StepActive := FALSE;
                    ELSE
                        MoveDown := TRUE;
                    END_IF;
                2: (* Grip *)
                    IF GripLimitSwitch THEN
                        StepActive := FALSE;
                    ELSE
                        ActivateGrip := TRUE;
                    END_IF;
                3: (* Up *)
                    IF UpLimitSwitch THEN
                        StepActive := FALSE;
                    ELSE
                        MoveUp := TRUE;
                    END_IF;
                4: (* Right *)
                    IF RightLimitSwitch THEN
                        StepActive := FALSE;
                    ELSE
                        MoveRight := TRUE;
                    END_IF;
                5: (* Down *)
                    IF DownLimitSwitch THEN
                        StepActive := FALSE;
                    ELSE
                        MoveDown := TRUE;
                    END_IF;
                6: (* Release *)
                    IF ReleaseLimitSwitch THEN
                        StepActive := FALSE;
                    ELSE
                        ActivateRelease := TRUE;
                    END_IF;
                7: (* Up *)
                    IF UpLimitSwitch THEN
                        StepActive := FALSE;
                    ELSE
                        MoveUp := TRUE;
                    END_IF;
                8: (* Left *)
                    IF LeftLimitSwitch THEN
                        StepActive := FALSE;
                    ELSE
                        MoveLeft := TRUE;
                    END_IF;
            END_CASE;
        END_IF;
    ELSE
        StepActive := FALSE;
        StepIndex  := 0;
    END_IF;

    (* ---------- Single cycle mode ---------- *)
    IF SingleCycleMode THEN
        CASE SingleCycleState OF
            0: (* Idle, wait for Start *)
                IF StartEdge THEN
                    SingleCycleState := 1;
                END_IF;
            1: (* Down *)
                IF DownLimitSwitch THEN
                    SingleCycleState := 2;
                ELSE
                    MoveDown := TRUE;
                END_IF;
            2: (* Grip *)
                IF GripLimitSwitch THEN
                    SingleCycleState := 3;
                ELSE
                    ActivateGrip := TRUE;
                END_IF;
            3: (* Up *)
                IF UpLimitSwitch THEN
                    SingleCycleState := 4;
                ELSE
                    MoveUp := TRUE;
                END_IF;
            4: (* Right *)
                IF RightLimitSwitch THEN
                    SingleCycleState := 5;
                ELSE
                    MoveRight := TRUE;
                END_IF;
            5: (* Down *)
                IF DownLimitSwitch THEN
                    SingleCycleState := 6;
                ELSE
                    MoveDown := TRUE;
                END_IF;
            6: (* Release *)
                IF ReleaseLimitSwitch THEN
                    SingleCycleState := 7;
                ELSE
                    ActivateRelease := TRUE;
                END_IF;
            7: (* Up *)
                IF UpLimitSwitch THEN
                    SingleCycleState := 8;
                ELSE
                    MoveUp := TRUE;
                END_IF;
            8: (* Left *)
                IF LeftLimitSwitch THEN
                    SingleCycleState := 9;
                ELSE
                    MoveLeft := TRUE;
                END_IF;
            9: (* Completed; wait for next Start *)
                IF StartEdge THEN
                    SingleCycleState := 1;
                END_IF;
        END_CASE;
    ELSE
        SingleCycleState := 0;
    END_IF;

    (* ---------- Continuous mode ---------- *)
    IF ContinuousMode THEN
        CASE ContinuousState OF
            0: (* Idle, wait for Start *)
                IF StartEdge THEN
                    ContinuousState := 1;
                END_IF;
            1: (* Down *)
                IF DownLimitSwitch THEN
                    ContinuousState := 2;
                ELSE
                    MoveDown := TRUE;
                END_IF;
            2: (* Grip *)
                IF GripLimitSwitch THEN
                    ContinuousState := 3;
                ELSE
                    ActivateGrip := TRUE;
                END_IF;
            3: (* Up *)
                IF UpLimitSwitch THEN
                    ContinuousState := 4;
                ELSE
                    MoveUp := TRUE;
                END_IF;
            4: (* Right *)
                IF RightLimitSwitch THEN
                    ContinuousState := 5;
                ELSE
                    MoveRight := TRUE;
                END_IF;
            5: (* Down *)
                IF DownLimitSwitch THEN
                    ContinuousState := 6;
                ELSE
                    MoveDown := TRUE;
                END_IF;
            6: (* Release *)
                IF ReleaseLimitSwitch THEN
                    ContinuousState := 7;
                ELSE
                    ActivateRelease := TRUE;
                END_IF;
            7: (* Up *)
                IF UpLimitSwitch THEN
                    ContinuousState := 8;
                ELSE
                    MoveUp := TRUE;
                END_IF;
            8: (* Left, then immediately start the next cycle *)
                IF LeftLimitSwitch THEN
                    ContinuousState := 1;
                ELSE
                    MoveLeft := TRUE;
                END_IF;
        END_CASE;
    ELSE
        ContinuousState := 0;
    END_IF;
END_IF;

END_FUNCTION_BLOCK