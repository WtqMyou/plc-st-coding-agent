Looking at the checkpoints and test failures, I need to identify the semantics issues:

1. **h05-13 failure**: SingleStepMode, Start=TRUE from previous FALSE state should advance to step 1 (MoveDown=TRUE), but observed is FALSE. This indicates the rising edge `tmp_StartRisingEdge` is not being consumed after use, causing it to persist and advance the step multiple times on the same scan until it passes step 1.

2. The rising edge flag persists across calls when Start remains TRUE, causing `tmp_Step` to skip past 1 before the CASE output assignment executes.

The fix: Clear `tmp_StartRisingEdge` immediately after consuming it at step 0 to ensure single-scan advancement semantics.

(* CONTRACT_RULES [] *)
FUNCTION_BLOCK ArmController
VAR_INPUT
    ManualMode      : BOOL;
    SingleStepMode  : BOOL;
    SingleCycleMode : BOOL;
    ContinuousMode  : BOOL;
    EmergencyStop   : BOOL;
    Start           : BOOL;
    DownButton      : BOOL;
    UpButton        : BOOL;
    LeftButton      : BOOL;
    RightButton     : BOOL;
    GripButton      : BOOL;
    ReleaseButton   : BOOL;
    DownLimitSwitch : BOOL;
    UpLimitSwitch   : BOOL;
    LeftLimitSwitch : BOOL;
    RightLimitSwitch: BOOL;
    GripLimitSwitch : BOOL;
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
    tmp_Step : INT := 0;
    tmp_StartPrev : BOOL := FALSE;
    tmp_StartRisingEdge : BOOL;
    tmp_StartReleased : BOOL := FALSE;
    tmp_ActionCompleted : BOOL := FALSE;
END_VAR

(*
ENGINEERING_CONTRACT
====================================================================================================
Output State: Activation | Retention/hold | Explicit reset | Same-scan priority | Units/boundaries
----------------------------------------------------------------------------------------------------
MoveDown:     Manual=button AND NOT limit; Step modes=per step CASE; EmergencyStop→FALSE
MoveUp:       Manual=button AND NOT limit; Step modes=per step CASE; EmergencyStop→FALSE
MoveLeft:     Manual=button AND NOT limit; Step modes=per step CASE; EmergencyStop→FALSE
MoveRight:    Manual=button AND NOT limit; Step modes=per step CASE; EmergencyStop→FALSE
ActivateGrip:     Manual=GripButton; Step modes=per step CASE using GripLimitSwitch; EmergencyStop→FALSE
ActivateRelease:  Manual=ReleaseButton; Step modes=per step CASE using ReleaseLimitSwitch; EmergencyStop→FALSE

Manual Mode (PUB001):
  - Direct button-to-output mapping, held while button pressed and NOT at limit position
  - Grip/Release: held while button pressed (limit switches are feedback only)
  - Priority: Highest; independent of step sequencer state

Single Step Mode (PUB003):
  - Step sequence: Down→Grip→Up→Right→Down→Release→Up→Left→(repeat)
  - Each action requires limit switch confirmation before next Start enables next step
  - Initial arm position: top-left (UpLimitSwitch=1, LeftLimitSwitch=1) [PUB002]
  - Step 0: Wait for Start rising edge, then execute step 1
  - Steps 1-7: Advance when current action completes AND (Start released since last press OR step>0)
  - Step 8: Wait for Start released then pressed again before cycling to step 0

Single Cycle Mode (PUB005):
  - Auto-execute all 8 steps sequentially on single Start press
  - Stops at step 8 (end state) after completing left movement
  - No automatic restart; next Start press required

Continuous Mode (PUB006):
  - Same 8-step sequence as single cycle
  - Automatic restart from step 0 when left movement completes (step→0)
  - Continuous looping until mode change or emergency stop

Emergency Stop (PUB007):
  - Trigger: EmergencyStop=FALSE
  - Effect: All outputs FALSE, step counter reset to 0
  - No automatic resume; requires mode re-activation after E-stop clears

PUB IDs: PUB001, PUB002, PUB003, PUB004, PUB005, PUB006, PUB007, PUB008, PUB009, PUB010, PUB011, PUB012, PUB013, PUB014, PUB015, PUB016, PUB017, PUB018, PUB019, PUB020
====================================================================================================
*)
tmp_StartRisingEdge := Start AND NOT tmp_StartPrev;

MoveDown := FALSE;
MoveUp := FALSE;
MoveLeft := FALSE;
MoveRight := FALSE;
ActivateGrip := FALSE;
ActivateRelease := FALSE;

IF EmergencyStop = FALSE THEN
    MoveDown := FALSE;
    MoveUp := FALSE;
    MoveLeft := FALSE;
    MoveRight := FALSE;
    ActivateGrip := FALSE;
    ActivateRelease := FALSE;
    tmp_Step := 0;
    tmp_StartPrev := Start;
    RETURN;
END_IF;

tmp_StartPrev := Start;

IF ManualMode THEN
    MoveDown := DownButton AND NOT DownLimitSwitch;
    MoveUp := UpButton AND NOT UpLimitSwitch;
    MoveLeft := LeftButton AND NOT LeftLimitSwitch;
    MoveRight := RightButton AND NOT RightLimitSwitch;
    ActivateGrip := GripButton;
    ActivateRelease := ReleaseButton;
ELSIF SingleStepMode THEN
    IF tmp_Step = 0 THEN
        IF tmp_StartRisingEdge THEN
            tmp_Step := 1;
            tmp_StartRisingEdge := FALSE;
        END_IF;
    ELSIF tmp_Step > 0 THEN
        tmp_ActionCompleted := FALSE;
        CASE tmp_Step OF
            1:
                MoveDown := TRUE;
                IF DownLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            2:
                ActivateGrip := TRUE;
                IF GripLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            3:
                MoveUp := TRUE;
                IF UpLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            4:
                MoveRight := TRUE;
                IF RightLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            5:
                MoveDown := TRUE;
                IF DownLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            6:
                ActivateRelease := TRUE;
                IF ReleaseLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            7:
                MoveUp := TRUE;
                IF UpLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            8:
                MoveLeft := TRUE;
                IF LeftLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
        END_CASE;
        IF tmp_ActionCompleted THEN
            tmp_Step := tmp_Step + 1;
            IF tmp_Step > 8 THEN
                tmp_Step := 8;
            END_IF;
            tmp_StartReleased := FALSE;
        END_IF;
        IF NOT Start THEN
            tmp_StartReleased := TRUE;
        END_IF;
        IF tmp_Step = 8 THEN
            IF tmp_StartRisingEdge AND tmp_StartReleased THEN
                tmp_Step := 0;
                tmp_StartReleased := FALSE;
            END_IF;
        ELSIF tmp_StartRisingEdge AND (tmp_StartReleased OR (tmp_Step > 0)) THEN
            tmp_Step := tmp_Step + 1;
            IF tmp_Step > 8 THEN
                tmp_Step := 8;
            END_IF;
            tmp_StartReleased := FALSE;
        END_IF;
    END_IF;
ELSIF SingleCycleMode THEN
    IF tmp_Step = 0 THEN
        IF tmp_StartRisingEdge THEN
            tmp_Step := 1;
            tmp_StartRisingEdge := FALSE;
        END_IF;
    ELSIF tmp_Step > 0 THEN
        tmp_ActionCompleted := FALSE;
        CASE tmp_Step OF
            1:
                MoveDown := TRUE;
                IF DownLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            2:
                ActivateGrip := TRUE;
                IF GripLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            3:
                MoveUp := TRUE;
                IF UpLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            4:
                MoveRight := TRUE;
                IF RightLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            5:
                MoveDown := TRUE;
                IF DownLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            6:
                ActivateRelease := TRUE;
                IF ReleaseLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            7:
                MoveUp := TRUE;
                IF UpLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            8:
                MoveLeft := TRUE;
                IF LeftLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
        END_CASE;
        IF tmp_ActionCompleted THEN
            tmp_Step := tmp_Step + 1;
            IF tmp_Step > 8 THEN
                tmp_Step := 8;
            END_IF;
        END_IF;
    END_IF;
ELSIF ContinuousMode THEN
    IF tmp_Step = 0 THEN
        IF tmp_StartRisingEdge THEN
            tmp_Step := 1;
            tmp_StartRisingEdge := FALSE;
        END_IF;
    ELSIF tmp_Step > 0 THEN
        tmp_ActionCompleted := FALSE;
        CASE tmp_Step OF
            1:
                MoveDown := TRUE;
                IF DownLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            2:
                ActivateGrip := TRUE;
                IF GripLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            3:
                MoveUp := TRUE;
                IF UpLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            4:
                MoveRight := TRUE;
                IF RightLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            5:
                MoveDown := TRUE;
                IF DownLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            6:
                ActivateRelease := TRUE;
                IF ReleaseLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            7:
                MoveUp := TRUE;
                IF UpLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
            8:
                MoveLeft := TRUE;
                IF LeftLimitSwitch THEN
                    tmp_ActionCompleted := TRUE;
                END_IF;
        END_CASE;
        IF tmp_ActionCompleted THEN
            tmp_Step := tmp_Step + 1;
            IF tmp_Step > 8 THEN
                tmp_Step := 0;
            END_IF;
        END_IF;
    END_IF;
END_IF;
END_FUNCTION_BLOCK