(* ENGINEERING_CONTRACT *)
(*
  PUB001: Manual mode - button activates output while held, stop at limit switch or release.
          Manual outputs: retention=hold_until_button_release OR limit, reset=button_release OR limit_reached.
  PUB002: Emergency stop - all outputs OFF, all state cleared. No retention. Reset=EmergencyStop=TRUE.
  PUB003-PUB012: Single step mode - 8-step sequence, Start to advance each step.
          Step outputs: retention=hold_until_limit, reset=limit_reached OR mode_exit.
          Step index 1..8 maps to: Down→Grip→Up→Right→Down→Release→Up→Left→(repeat).
  PUB013-PUB014: Single cycle mode - auto-execute 8 steps on Start, stop at home.
          Same output retention as PUB003-PUB012. Cycle reset=mode_exit only.
  PUB015-PUB016: Continuous mode - same as single cycle but repeat after home.
          Cycle restart trigger: timer PT after home, if Start still asserted.
  PUB017: GripLimitSwitch/ReleaseLimitSwitch signal action completion (not position).
          Grip/Release output: activation=entry_unless_limit, retention=limit FALSE,
          deactivation=limit TRUE (same scan). No explicit reset input.
  PUB018: Caller guarantees mutually exclusive mode inputs.
  PUB019: Opposite-direction pairs (Up/Down, Left/Right) must never energize together.
          Implementation: output TRUE only when opposite limit is FALSE.
  PUB020: Single step confirmation = Start button release, not level.
*)
(* CONTRACT_RULES [] *)

TYPE ArmStep : INT (Idle := 0, Step1 := 1, Step2 := 2, Step3 := 3, Step4 := 4,
                     Step5 := 5, Step6 := 6, Step7 := 7, Step8 := 8)
END_TYPE

FUNCTION_BLOCK ArmController
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
    tmp_CurrentStep   : ArmStep := ArmStep.Idle;
    tmp_StartTrigger  : BOOL;
    tmp_StartReleased : BOOL;
    tmp_Gripping      : BOOL;
    tmp_Releasing     : BOOL;
    tmp_CycleDoneTimer : TON;
END_VAR

// Emergency stop: clears all outputs and state
IF EmergencyStop THEN
    MoveDown       := FALSE;
    MoveUp         := FALSE;
    MoveLeft       := FALSE;
    MoveRight      := FALSE;
    ActivateGrip   := FALSE;
    ActivateRelease := FALSE;
    tmp_CurrentStep   := ArmStep.Idle;
    tmp_StartTrigger  := FALSE;
    tmp_StartReleased := FALSE;
    tmp_Gripping      := FALSE;
    tmp_Releasing     := FALSE;
    tmp_CycleDoneTimer(IN := FALSE, PT := T#0s);
    RETURN;
END_IF;

// Default all outputs OFF
MoveDown       := FALSE;
MoveUp         := FALSE;
MoveLeft       := FALSE;
MoveRight      := FALSE;
ActivateGrip   := FALSE;
ActivateRelease := FALSE;

IF ManualMode THEN
    // Direct button-to-output mapping, stop at limit switch
    MoveDown       := DownButton AND NOT DownLimitSwitch;
    MoveUp         := UpButton AND NOT UpLimitSwitch;
    MoveLeft       := LeftButton AND NOT LeftLimitSwitch;
    MoveRight      := RightButton AND NOT RightLimitSwitch;
    ActivateGrip   := GripButton AND NOT GripLimitSwitch;
    ActivateRelease := ReleaseButton AND NOT ReleaseLimitSwitch;

ELSIF SingleStepMode THEN
    // Rising-edge Start advances through steps; each step waits for limit switch
    IF tmp_StartReleased AND NOT Start AND tmp_CurrentStep = ArmStep.Idle THEN
        tmp_StartTrigger := TRUE;
    END_IF
    tmp_StartReleased := Start;

    IF tmp_CurrentStep = ArmStep.Idle THEN
        IF tmp_StartTrigger THEN
            tmp_CurrentStep := ArmStep.Step1;
            tmp_StartTrigger := FALSE;
        END_IF;
    ELSE
        CASE TO_INT(tmp_CurrentStep) OF
            1: MoveDown := NOT DownLimitSwitch;
               IF DownLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step2;
               END_IF;
            2: ActivateGrip := NOT GripLimitSwitch;
               IF GripLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step3;
               END_IF;
            3: MoveUp := NOT UpLimitSwitch;
               IF UpLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step4;
               END_IF;
            4: MoveRight := NOT RightLimitSwitch;
               IF RightLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step5;
               END_IF;
            5: MoveDown := NOT DownLimitSwitch;
               IF DownLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step6;
               END_IF;
            6: ActivateRelease := NOT ReleaseLimitSwitch;
               IF ReleaseLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step7;
               END_IF;
            7: MoveUp := NOT UpLimitSwitch;
               IF UpLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step8;
               END_IF;
            8: MoveLeft := NOT LeftLimitSwitch;
               IF LeftLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Idle;
               END_IF;
        END_CASE;
    END_IF;

ELSIF SingleCycleMode THEN
    // Start triggers auto-sequence; cycle completes and stops at home
    IF Start AND tmp_CurrentStep = ArmStep.Idle AND NOT tmp_Gripping AND NOT tmp_Releasing THEN
        tmp_StartTrigger := TRUE;
    END_IF;

    // Cycle completion: at Step8 and home (UpLimitSwitch AND LeftLimitSwitch)
    IF tmp_CurrentStep = ArmStep.Step8 AND UpLimitSwitch AND LeftLimitSwitch THEN
        tmp_CycleDoneTimer(IN := TRUE, PT := T#1ms);
        IF tmp_CycleDoneTimer.Q THEN
            tmp_StartTrigger  := FALSE;
            tmp_Gripping      := FALSE;
            tmp_Releasing     := FALSE;
            tmp_CurrentStep   := ArmStep.Idle;
        END_IF;
    ELSE
        tmp_CycleDoneTimer(IN := FALSE, PT := T#0s);
    END_IF;

    IF tmp_StartTrigger THEN
        CASE TO_INT(tmp_CurrentStep) OF
            0: tmp_CurrentStep := ArmStep.Step1;
            1: MoveDown := NOT DownLimitSwitch;
               IF DownLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step2;
               END_IF;
            2: ActivateGrip := NOT GripLimitSwitch;
               IF GripLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step3;
               END_IF;
            3: MoveUp := NOT UpLimitSwitch;
               IF UpLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step4;
               END_IF;
            4: MoveRight := NOT RightLimitSwitch;
               IF RightLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step5;
               END_IF;
            5: MoveDown := NOT DownLimitSwitch;
               IF DownLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step6;
               END_IF;
            6: ActivateRelease := NOT ReleaseLimitSwitch;
               IF ReleaseLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step7;
               END_IF;
            7: MoveUp := NOT UpLimitSwitch;
               IF UpLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step8;
               END_IF;
            8: MoveLeft := NOT LeftLimitSwitch;
               IF LeftLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Idle;
               END_IF;
        END_CASE;
    END_IF;

ELSIF ContinuousMode THEN
    // Same as single cycle but restarts automatically after PT delay at home
    IF Start AND NOT tmp_Gripping AND NOT tmp_Releasing THEN
        tmp_StartTrigger := TRUE;
    END_IF;

    IF tmp_CurrentStep = ArmStep.Step8 AND UpLimitSwitch AND LeftLimitSwitch THEN
        tmp_CycleDoneTimer(IN := tmp_CycleDoneTimer.Q, PT := T#1ms);
        IF tmp_CycleDoneTimer.Q THEN
            tmp_CurrentStep := ArmStep.Idle;
        END_IF;
        IF NOT tmp_CycleDoneTimer.Q AND tmp_CurrentStep = ArmStep.Idle THEN
            tmp_StartTrigger := Start;
            tmp_Gripping     := FALSE;
            tmp_Releasing    := FALSE;
        END_IF;
    ELSE
        tmp_CycleDoneTimer(IN := FALSE, PT := T#0s);
    END_IF;

    IF tmp_StartTrigger THEN
        CASE TO_INT(tmp_CurrentStep) OF
            0: tmp_CurrentStep := ArmStep.Step1;
            1: MoveDown := NOT DownLimitSwitch;
               IF DownLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step2;
               END_IF;
            2: ActivateGrip := NOT GripLimitSwitch;
               IF GripLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step3;
               END_IF;
            3: MoveUp := NOT UpLimitSwitch;
               IF UpLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step4;
               END_IF;
            4: MoveRight := NOT RightLimitSwitch;
               IF RightLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step5;
               END_IF;
            5: MoveDown := NOT DownLimitSwitch;
               IF DownLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step6;
               END_IF;
            6: ActivateRelease := NOT ReleaseLimitSwitch;
               IF ReleaseLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step7;
               END_IF;
            7: MoveUp := NOT UpLimitSwitch;
               IF UpLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Step8;
               END_IF;
            8: MoveLeft := NOT LeftLimitSwitch;
               IF LeftLimitSwitch THEN
                   tmp_CurrentStep := ArmStep.Idle;
               END_IF;
        END_CASE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK