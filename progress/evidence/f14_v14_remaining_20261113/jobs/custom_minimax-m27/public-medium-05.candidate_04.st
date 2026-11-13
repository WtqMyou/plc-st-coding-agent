(* ENGINEERING_CONTRACT
 * =============================================================================
 * Mode Switching (PUB001): Mode=0 manual, Mode=1 automatic. Output state on
 *   mode transition: both Motor outputs cleared, CompletionLight cleared.
 *   Transition detected via rising edge on Mode input variable.
 * Manual Mode (PUB002/PUB003):
 *   - Activation: Mode=0
 *   - Retention: MotorForward holds while ForwardButton=1 AND ReverseButton=0
 *   - Retention: MotorReverse holds while ReverseButton=1 AND ForwardButton=0
 *   - Deactivation: both cleared on any of: ForwardButton=0, ReverseButton=0,
 *     forward+reverse both asserted (interlock drops both), or Mode→1
 *   - Units: combinational, no timer
 * Automatic Mode (PUB004-PUB008):
 *   - Scan behavior: edge-sensitive state machine evaluated every scan
 *   - STATION_A activation: SensorA=TRUE AND State=IDLE
 *   - STATION_B activation: SensorB=TRUE AND State=MOVING_TO_B
 *   - STATION_C activation: SensorC=TRUE AND State=MOVING_TO_C
 *   - MotorForward activation: (State=IDLE AND SensorA=TRUE→ButtonA=TRUE)
 *     OR (State=STATION_A AND ButtonA=TRUE) OR (State=STATION_B AND ButtonB=TRUE)
 *   - MotorForward deactivation: on SensorB (→STATION_B) or SensorC (→STATION_C)
 *   - CompletionLight activation: SensorC=TRUE AND ButtonC=TRUE AND State=STATION_C
 *   - CompletionLight retention: holds until SensorC=FALSE (product removed)
 *   - CompletionLight deactivation: SensorC=FALSE transitions to IDLE
 *   - IDLE reset: State=IDLE when no product detected at any station
 *   - Units: boolean states, no timers
 * Same-scan priority: manual overrides automatic (Mode check first). Within
 *   automatic, state transition clears prior MotorForward before next sensor
 *   evaluation; CompletionLight set after Mode/state checks finalized.
 * Physical interlock: Pub002 prohibits MotorForward AND MotorReverse together.
 * =============================================================================
 *)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK ProductionLineControl
VAR_INPUT
    Mode            : BOOL;  (* 0=manual, 1=automatic *)
    ForwardButton   : BOOL;
    ReverseButton   : BOOL;
    SensorA         : BOOL;
    SensorB         : BOOL;
    SensorC         : BOOL;
    ButtonA         : BOOL;
    ButtonB         : BOOL;
    ButtonC         : BOOL;
END_VAR
VAR_OUTPUT
    MotorForward    : BOOL;
    MotorReverse    : BOOL;
    CompletionLight : BOOL;
END_VAR
VAR_CONSTANT
    IDLE         : INT := 0;
    STATION_A    : INT := 1;
    MOVING_TO_B  : INT := 2;
    STATION_B    : INT := 3;
    MOVING_TO_C  : INT := 4;
    STATION_C    : INT := 5;
END_VAR_CONSTANT

VAR
    State           : INT;  (* 0=IDLE, 1=STATION_A, 2=MOVING_TO_B, 3=STATION_B,
                                4=MOVING_TO_C, 5=STATION_C *)
    tmp_PreviousMode : BOOL;
    tmp_ModeRising   : BOOL;
END_VAR

    (* Constants for state identification *)
    (* Detect mode transition for reset behavior *)
    tmp_ModeRising := Mode AND NOT tmp_PreviousMode;
    tmp_PreviousMode := Mode;

    (* Reset outputs on mode entry into automatic *)
    IF tmp_ModeRising THEN
        MotorForward    := FALSE;
        MotorReverse    := FALSE;
        CompletionLight := FALSE;
    END_IF;

    (* Mode-based operation dispatch *)
    IF Mode = FALSE THEN
        (* Manual Mode (PUB002/PUB003) *)
        (* Interlock: forward and reverse cannot be energized together *)
        IF ForwardButton AND NOT ReverseButton THEN
            MotorForward := TRUE;
            MotorReverse := FALSE;
        ELSIF ReverseButton AND NOT ForwardButton THEN
            MotorForward := FALSE;
            MotorReverse := TRUE;
        ELSE
            MotorForward := FALSE;
            MotorReverse := FALSE;
        END_IF;
    ELSE
        (* Automatic Mode (PUB004-PUB008) *)
        MotorForward    := FALSE;
        MotorReverse    := FALSE;

        (* State machine evaluation *)
        CASE State OF
            IDLE :
                (* Wait for product at Workstation A *)
                IF SensorA THEN
                    State := STATION_A;
                END_IF;

            STATION_A :
                (* Product at Workstation A, wait for ButtonA *)
                IF ButtonA THEN
                    MotorForward := TRUE;
                    State := MOVING_TO_B;
                END_IF;
                (* Fallback: if product leaves A unexpectedly, return to IDLE *)
                IF NOT SensorA THEN
                    State := IDLE;
                END_IF;

            MOVING_TO_B :
                (* Motor running forward, wait for SensorB *)
                MotorForward := TRUE;
                IF SensorB THEN
                    MotorForward := FALSE;
                    State := STATION_B;
                END_IF;

            STATION_B :
                (* Product at Workstation B, wait for ButtonB *)
                IF ButtonB THEN
                    MotorForward := TRUE;
                    State := MOVING_TO_C;
                END_IF;
                (* Fallback: if product leaves B unexpectedly, return to IDLE *)
                IF NOT SensorB THEN
                    State := IDLE;
                END_IF;

            MOVING_TO_C :
                (* Motor running forward, wait for SensorC *)
                MotorForward := TRUE;
                IF SensorC THEN
                    MotorForward := FALSE;
                    State := STATION_C;
                END_IF;

            STATION_C :
                (* Product at Workstation C, wait for ButtonC, then product removal *)
                IF ButtonC THEN
                    CompletionLight := TRUE;
                END_IF;
                (* Product taken away: light off, return to IDLE *)
                IF NOT SensorC THEN
                    CompletionLight := FALSE;
                    State := IDLE;
                END_IF;

        END_CASE;
    END_IF;

END_FUNCTION_BLOCK