(* ENGINEERING_CONTRACT
MotorForward (auto): activated by state machine transfer legs PUB003/PUB004; held while state; off at target sensor or manual PUB002.
MotorForward (manual): ForwardButton level, interlocked; PUB002.
MotorReverse (manual): ReverseButton level, interlocked; both buttons -> both off.
kick: unqualified after weightComplete at weighing; latched until SensorWeight false (unspecified removal); PUB004.
CompletionLight: on at SensorOutput arrival after firing, held until SensorOutput false; PUB004.
firingTemp: linear 100->500, 200->550 inclusive; set on qualified weighing; retained otherwise; PUB004.
State localState: retained across scans; mode switch does not reset; unspecified reset on mode change.
*)
(* CONTRACT_RULES [] *)
TYPE ProductionLineState :
(
    STATE_IDLE,
    STATE_MOVING_TO_WASH,
    STATE_AT_WASH,
    STATE_MOVING_TO_WEIGH,
    STATE_AT_WEIGH,
    STATE_MOVING_TO_FIRING,
    STATE_AT_FIRING,
    STATE_MOVING_TO_OUTPUT,
    STATE_AT_OUTPUT
);
END_TYPE;

FUNCTION_BLOCK ProductionControl
VAR_INPUT
    Mode : BOOL;
    ForwardButton : BOOL;
    ReverseButton : BOOL;
    SensorFeed : BOOL;
    SensorWash : BOOL;
    SensorWeight : BOOL;
    SensorFiring : BOOL;
    SensorOutput : BOOL;
    washComplete : BOOL;
    weightComplete : BOOL;
    weight : REAL;
    firingComplete : BOOL;
END_VAR
VAR_OUTPUT
    MotorForward : BOOL;
    MotorReverse : BOOL;
    kick : BOOL;
    CompletionLight : BOOL;
    firingTemp : REAL;
END_VAR
VAR
    localState : ProductionLineState := STATE_IDLE;
    localKickActive : BOOL := FALSE;
END_VAR

IF Mode THEN
    MotorReverse := FALSE;

    CASE localState OF
        STATE_IDLE:
            MotorForward := FALSE;
            CompletionLight := FALSE;
            kick := FALSE;
            localKickActive := FALSE;
            IF SensorFeed THEN
                MotorForward := TRUE;
                localState := STATE_MOVING_TO_WASH;
            END_IF;

        STATE_MOVING_TO_WASH:
            MotorForward := TRUE;
            IF SensorWash THEN
                MotorForward := FALSE;
                localState := STATE_AT_WASH;
            END_IF;

        STATE_AT_WASH:
            MotorForward := FALSE;
            IF washComplete THEN
                MotorForward := TRUE;
                localState := STATE_MOVING_TO_WEIGH;
            END_IF;

        STATE_MOVING_TO_WEIGH:
            MotorForward := TRUE;
            IF SensorWeight THEN
                MotorForward := FALSE;
                localState := STATE_AT_WEIGH;
            END_IF;

        STATE_AT_WEIGH:
            MotorForward := FALSE;
            IF localKickActive THEN
                IF NOT SensorWeight THEN
                    kick := FALSE;
                    localKickActive := FALSE;
                    localState := STATE_IDLE;
                END_IF;
            ELSIF weightComplete THEN
                IF (weight >= 100.0) AND (weight <= 200.0) THEN
                    firingTemp := 500.0 + (weight - 100.0) * 0.5;
                    kick := FALSE;
                    localKickActive := FALSE;
                    MotorForward := TRUE;
                    localState := STATE_MOVING_TO_FIRING;
                ELSE
                    kick := TRUE;
                    localKickActive := TRUE;
                    MotorForward := FALSE;
                END_IF;
            END_IF;

        STATE_MOVING_TO_FIRING:
            MotorForward := TRUE;
            IF SensorFiring THEN
                MotorForward := FALSE;
                localState := STATE_AT_FIRING;
            END_IF;

        STATE_AT_FIRING:
            MotorForward := FALSE;
            IF firingComplete THEN
                MotorForward := TRUE;
                localState := STATE_MOVING_TO_OUTPUT;
            END_IF;

        STATE_MOVING_TO_OUTPUT:
            MotorForward := TRUE;
            CompletionLight := FALSE;
            IF SensorOutput THEN
                MotorForward := FALSE;
                CompletionLight := TRUE;
                localState := STATE_AT_OUTPUT;
            END_IF;

        STATE_AT_OUTPUT:
            MotorForward := FALSE;
            CompletionLight := TRUE;
            IF NOT SensorOutput THEN
                CompletionLight := FALSE;
                localState := STATE_IDLE;
            END_IF;
    END_CASE;

ELSE
    MotorForward := ForwardButton AND (NOT ReverseButton);
    MotorReverse := ReverseButton AND (NOT ForwardButton);
    (* kick, CompletionLight, firingTemp retain their last automatic values *)
END_IF;

END_FUNCTION_BLOCK