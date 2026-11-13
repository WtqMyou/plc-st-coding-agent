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
    local_startR : R_TRIG;
    tmp_first_scan : BOOL := TRUE;
    tmp_start_pulse : BOOL;
    tmp_not_estop : BOOL;
    tmp_ss_step : INT := 0;
    tmp_ss_busy : BOOL := FALSE;
    tmp_auto_running : BOOL := FALSE;
    tmp_auto_step : INT := 0;
    tmp_cmd_step : INT := 0;
    tmp_cmd_active : BOOL := FALSE;
    tmp_limit_reached : BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT
   Outputs MoveDown/Up/Left/Right/ActivateGrip/ActivateRelease:
   - Activate: manual while button=1, not at axis limit, and no opposite button (PUB001,PUB020); auto while current step active.
   - Retain: none latching; auto sequence state retained until completion/estop.
   - Reset: EmergencyStop=FALSE forces all outputs off and resets auto/single-step state (PUB005).
   - Same-scan: on limit true, previous output off; auto cycle can start next output in same scan (PUB003,PUB004).
   - Manual opposite-direction conflict inhibits both (PUB001 + shared rule).
   - Single-step Start edge only when not busy; ignored during running action (PUB002).
   - Single-cycle/continuous Start edge only when not running; continuous wraps at left completion (PUB003,PUB004).
   - Steps 0..7 = down, grip, up, right, down, release, up, left.
   - Grip/Release completion via GripLimitSwitch/ReleaseLimitSwitch (PUB001,PUB002).
   - Unspecified: mode change outside selected branch aborts/pauses per branch.
*)

(* CONTRACT_RULES [] *)

MoveDown := FALSE;
MoveUp := FALSE;
MoveLeft := FALSE;
MoveRight := FALSE;
ActivateGrip := FALSE;
ActivateRelease := FALSE;

tmp_not_estop := EmergencyStop; (* TRUE means no emergency stop triggered *)

local_startR(CLK := Start);
tmp_start_pulse := local_startR.Q AND NOT tmp_first_scan;
tmp_first_scan := FALSE;

tmp_cmd_active := FALSE;
tmp_cmd_step := 0;

IF NOT tmp_not_estop THEN
    tmp_ss_step := 0;
    tmp_ss_busy := FALSE;
    tmp_auto_running := FALSE;
    tmp_auto_step := 0;
    RETURN;
END_IF;

IF ManualMode THEN
    IF DownButton AND NOT UpButton AND NOT DownLimitSwitch THEN
        MoveDown := TRUE;
    END_IF;
    IF UpButton AND NOT DownButton AND NOT UpLimitSwitch THEN
        MoveUp := TRUE;
    END_IF;
    IF LeftButton AND NOT RightButton AND NOT LeftLimitSwitch THEN
        MoveLeft := TRUE;
    END_IF;
    IF RightButton AND NOT LeftButton AND NOT RightLimitSwitch THEN
        MoveRight := TRUE;
    END_IF;
    IF GripButton AND NOT ReleaseButton AND NOT GripLimitSwitch THEN
        ActivateGrip := TRUE;
    END_IF;
    IF ReleaseButton AND NOT GripButton AND NOT ReleaseLimitSwitch THEN
        ActivateRelease := TRUE;
    END_IF;

ELSIF SingleStepMode THEN
    IF tmp_start_pulse AND NOT tmp_ss_busy THEN
        tmp_ss_busy := TRUE;
    END_IF;

    IF tmp_ss_busy THEN
        tmp_limit_reached := FALSE;
        CASE tmp_ss_step OF
            0: tmp_limit_reached := DownLimitSwitch;
            1: tmp_limit_reached := GripLimitSwitch;
            2: tmp_limit_reached := UpLimitSwitch;
            3: tmp_limit_reached := RightLimitSwitch;
            4: tmp_limit_reached := DownLimitSwitch;
            5: tmp_limit_reached := ReleaseLimitSwitch;
            6: tmp_limit_reached := UpLimitSwitch;
            7: tmp_limit_reached := LeftLimitSwitch;
        END_CASE;

        IF tmp_limit_reached THEN
            tmp_ss_busy := FALSE;
            tmp_ss_step := tmp_ss_step + 1;
            IF tmp_ss_step > 7 THEN
                tmp_ss_step := 0;
            END_IF;
        ELSE
            tmp_cmd_step := tmp_ss_step;
            tmp_cmd_active := TRUE;
        END_IF;
    END_IF;

ELSIF SingleCycleMode OR ContinuousMode THEN
    IF tmp_start_pulse AND NOT tmp_auto_running THEN
        tmp_auto_running := TRUE;
        tmp_auto_step := 0;
    END_IF;

    IF tmp_auto_running THEN
        tmp_limit_reached := FALSE;
        CASE tmp_auto_step OF
            0: tmp_limit_reached := DownLimitSwitch;
            1: tmp_limit_reached := GripLimitSwitch;
            2: tmp_limit_reached := UpLimitSwitch;
            3: tmp_limit_reached := RightLimitSwitch;
            4: tmp_limit_reached := DownLimitSwitch;
            5: tmp_limit_reached := ReleaseLimitSwitch;
            6: tmp_limit_reached := UpLimitSwitch;
            7: tmp_limit_reached := LeftLimitSwitch;
        END_CASE;

        IF tmp_limit_reached THEN
            IF tmp_auto_step = 7 THEN
                IF ContinuousMode THEN
                    tmp_auto_step := 0; (* start next cycle *)
                ELSE
                    tmp_auto_running := FALSE;
                    tmp_auto_step := 0;
                END_IF;
            ELSE
                tmp_auto_step := tmp_auto_step + 1;
            END_IF;
        END_IF;

        IF tmp_auto_running THEN
            tmp_cmd_step := tmp_auto_step;
            tmp_cmd_active := TRUE;
        END_IF;
    END_IF;
END_IF;

IF tmp_cmd_active THEN
    CASE tmp_cmd_step OF
        0: MoveDown := TRUE;
        1: ActivateGrip := TRUE;
        2: MoveUp := TRUE;
        3: MoveRight := TRUE;
        4: MoveDown := TRUE;
        5: ActivateRelease := TRUE;
        6: MoveUp := TRUE;
        7: MoveLeft := TRUE;
    END_CASE;
END_IF;

END_FUNCTION_BLOCK