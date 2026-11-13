(* ENGINEERING_CONTRACT - Mechanical Arm Control
 * =============================================================================
 * Mode Selection: Caller ensures exactly one mode active; emergency stop has highest priority.
 * 
 * Output State Table:
 * | Output          | Activation                              | Retention                     | Reset                        | Priority    |
 * |-----------------|-----------------------------------------|-------------------------------|--------------------------------|-------------|
 * | MoveDown        | Manual:DownButton AND NOT DownLimitSwitch| Manual:button hold; Auto:step | EmergencyStop, step change   | Physical dir |
 * |                 | Auto: current step = down step           | Auto: hold until limit        | button release (manual)       | rule applies |
 * | MoveUp          | Manual:UpButton AND NOT UpLimitSwitch    | Manual:button hold; Auto:step | EmergencyStop, step change   | Physical dir |
 * |                 | Auto: current step = up step             | Auto: hold until limit        | button release (manual)       | rule applies |
 * | MoveLeft        | Manual:LeftButton AND NOT LeftLimitSwitch| Manual:button hold; Auto:step | EmergencyStop, step change   | Physical dir |
 * |                 | Auto: current step = left step           | Auto: hold until limit        | button release (manual)       | rule applies |
 * | MoveRight       | Manual:RightButton AND NOT RightLimitSwitch| Manual:button hold; Auto:step| EmergencyStop, step change   | Physical dir |
 * |                 | Auto: current step = right step          | Auto: hold until limit        | button release (manual)       | rule applies |
 * | ActivateGrip    | Manual:GripButton AND NOT GripLimitSwitch| Manual:button hold; Auto:step | EmergencyStop, step change   | N/A         |
 * |                 | Auto: grip step, hold until GripLimitSwitch| Auto: hold until limit       | button release (manual)       |             |
 * | ActivateRelease | Manual:ReleaseButton AND NOT ReleaseLimitSwitch| Manual:button hold; Auto:step| EmergencyStop, step change  | N/A         |
 * |                 | Auto: release step, hold until ReleaseLimitSwitch| Auto: hold until limit    | button release (manual)       |             |
 * 
 * Sequence (8 steps, single cycle and continuous modes):
 *   0: Down -> 1: Grip -> 2: Up -> 3: Right -> 4: Down -> 5: Release -> 6: Up -> 7: Left -> (repeat)
 * 
 * Single step mode: Same 8-step sequence, advancing one step per Start rising edge.
 * Single cycle mode: Executes all 8 steps, stops at stepIndex=8.
 * Continuous mode: Executes all 8 steps, returns to stepIndex=0 when complete.
 * 
 * Units: Limit switches TRUE=at position (normally-open, closed at position).
 * Boundary: stepIndex ∈ [0..8]; 8 = cycle complete state for single cycle mode.
 * Same-scan: Final output evaluated from current stepIndex and limit switches per scan.
 * 
 * Contract PUB clauses: PUB001-PUB020 define all behavior above.
 *)

FUNCTION_BLOCK ArmController
VAR
    stepIndex : INT := 0;         // Current step in sequence (0-7), 8 = single cycle complete
    startButtonPrev : BOOL := FALSE; // Rising edge detection for Start button
    tmpRisingEdge : BOOL;
END_VAR

(* CONTRACT_RULES
[
  {"kind": "hold_until_reset", "output": "MoveDown", "set_input": "DownButton", "reset_input": null},
  {"kind": "hold_until_reset", "output": "MoveUp", "set_input": "UpButton", "reset_input": null},
  {"kind": "hold_until_reset", "output": "MoveLeft", "set_input": "LeftButton", "reset_input": null},
  {"kind": "hold_until_reset", "output": "MoveRight", "set_input": "RightButton", "reset_input": null},
  {"kind": "hold_until_reset", "output": "ActivateGrip", "set_input": "GripButton", "reset_input": null},
  {"kind": "hold_until_reset", "output": "ActivateRelease", "set_input": "ReleaseButton", "reset_input": null}
]
*)

    // Emergency stop has highest priority - stops all outputs
    IF EmergencyStop = FALSE THEN
        MoveDown := FALSE;
        MoveUp := FALSE;
        MoveLeft := FALSE;
        MoveRight := FALSE;
        ActivateGrip := FALSE;
        ActivateRelease := FALSE;
    ELSIF SingleStepMode THEN
        // Detect rising edge on Start button
        tmpRisingEdge := Start AND NOT startButtonPrev;
        startButtonPrev := Start;

        IF tmpRisingEdge THEN
            stepIndex := stepIndex + 1;
            IF stepIndex > 7 THEN
                stepIndex := 0;
            END_IF
        END_IF

        // Execute current step
        CASE stepIndex OF
            0: // Down
                MoveDown := TRUE;
                IF DownLimitSwitch THEN
                    stepIndex := 1;
                END_IF
            1: // Grip
                ActivateGrip := TRUE;
                IF GripLimitSwitch THEN
                    stepIndex := 2;
                END_IF
            2: // Up
                MoveUp := TRUE;
                IF UpLimitSwitch THEN
                    stepIndex := 3;
                END_IF
            3: // Right
                MoveRight := TRUE;
                IF RightLimitSwitch THEN
                    stepIndex := 4;
                END_IF
            4: // Down (second descent)
                MoveDown := TRUE;
                IF DownLimitSwitch THEN
                    stepIndex := 5;
                END_IF
            5: // Release
                ActivateRelease := TRUE;
                IF ReleaseLimitSwitch THEN
                    stepIndex := 6;
                END_IF
            6: // Up (second ascent)
                MoveUp := TRUE;
                IF UpLimitSwitch THEN
                    stepIndex := 7;
                END_IF
            7: // Left (return to start)
                MoveLeft := TRUE;
                IF LeftLimitSwitch THEN
                    stepIndex := 0;
                END_IF
        END_CASE

    ELSIF SingleCycleMode THEN
        // Single cycle mode: run through all steps automatically, stop at end
        CASE stepIndex OF
            0:
                MoveDown := NOT DownLimitSwitch;
                IF DownLimitSwitch THEN
                    stepIndex := 1;
                END_IF
            1:
                ActivateGrip := NOT GripLimitSwitch;
                IF GripLimitSwitch THEN
                    stepIndex := 2;
                END_IF
            2:
                MoveUp := NOT UpLimitSwitch;
                IF UpLimitSwitch THEN
                    stepIndex := 3;
                END_IF
            3:
                MoveRight := NOT RightLimitSwitch;
                IF RightLimitSwitch THEN
                    stepIndex := 4;
                END_IF
            4:
                MoveDown := NOT DownLimitSwitch;
                IF DownLimitSwitch THEN
                    stepIndex := 5;
                END_IF
            5:
                ActivateRelease := NOT ReleaseLimitSwitch;
                IF ReleaseLimitSwitch THEN
                    stepIndex := 6;
                END_IF
            6:
                MoveUp := NOT UpLimitSwitch;
                IF UpLimitSwitch THEN
                    stepIndex := 7;
                END_IF
            7:
                MoveLeft := NOT LeftLimitSwitch;
                IF LeftLimitSwitch THEN
                    stepIndex := 8; // Cycle complete, stay here
                END_IF
        END_CASE

    ELSIF ContinuousMode THEN
        // Continuous mode: run through all steps automatically, restart at end
        CASE stepIndex OF
            0:
                MoveDown := NOT DownLimitSwitch;
                IF DownLimitSwitch THEN
                    stepIndex := 1;
                END_IF
            1:
                ActivateGrip := NOT GripLimitSwitch;
                IF GripLimitSwitch THEN
                    stepIndex := 2;
                END_IF
            2:
                MoveUp := NOT UpLimitSwitch;
                IF UpLimitSwitch THEN
                    stepIndex := 3;
                END_IF
            3:
                MoveRight := NOT RightLimitSwitch;
                IF RightLimitSwitch THEN
                    stepIndex := 4;
                END_IF
            4:
                MoveDown := NOT DownLimitSwitch;
                IF DownLimitSwitch THEN
                    stepIndex := 5;
                END_IF
            5:
                ActivateRelease := NOT ReleaseLimitSwitch;
                IF ReleaseLimitSwitch THEN
                    stepIndex := 6;
                END_IF
            6:
                MoveUp := NOT UpLimitSwitch;
                IF UpLimitSwitch THEN
                    stepIndex := 7;
                END_IF
            7:
                MoveLeft := NOT LeftLimitSwitch;
                IF LeftLimitSwitch THEN
                    stepIndex := 0; // Restart cycle
                END_IF
        END_CASE

    ELSIF ManualMode THEN
        // Manual mode: direct button control with limit switch protection
        MoveDown := DownButton AND NOT DownLimitSwitch;
        MoveUp := UpButton AND NOT UpLimitSwitch;
        MoveLeft := LeftButton AND NOT LeftLimitSwitch;
        MoveRight := RightButton AND NOT RightLimitSwitch;
        ActivateGrip := GripButton AND NOT GripLimitSwitch;
        ActivateRelease := ReleaseButton AND NOT ReleaseLimitSwitch;
    END_IF

END_FUNCTION_BLOCK