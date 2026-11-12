TYPE T_PRODUCTION_STATE :
(
    IDLE,
    MOVING_FEED_TO_WASH,
    AT_WASH,
    MOVING_WASH_TO_WEIGHT,
    AT_WEIGHT_WAIT,
    AT_WEIGHT_REJECT,
    MOVING_WEIGHT_TO_FIRING,
    AT_FIRING,
    MOVING_FIRING_TO_OUTPUT,
    AT_OUTPUT
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
    currentState : T_PRODUCTION_STATE := IDLE;
END_VAR

IF Mode = FALSE THEN
    // Manual mode
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
    // Reset all automatic outputs and state
    kick := FALSE;
    CompletionLight := FALSE;
    firingTemp := 0.0;
    currentState := IDLE;
ELSE
    // Automatic mode
    // Set default outputs for this scan
    MotorReverse := FALSE;
    MotorForward := FALSE;
    kick := FALSE;
    CompletionLight := FALSE;
    // firingTemp retains its last calculated value unless updated in qualified weighing

    CASE currentState OF
        IDLE:
            IF SensorFeed THEN
                currentState := MOVING_FEED_TO_WASH;
                MotorForward := TRUE;
            END_IF;

        MOVING_FEED_TO_WASH:
            MotorForward := TRUE;
            IF SensorWash THEN
                MotorForward := FALSE;
                currentState := AT_WASH;
            END_IF;

        AT_WASH:
            IF washComplete THEN
                MotorForward := TRUE;
                currentState := MOVING_WASH_TO_WEIGHT;
            END_IF;

        MOVING_WASH_TO_WEIGHT:
            MotorForward := TRUE;
            IF SensorWeight THEN
                MotorForward := FALSE;
                currentState := AT_WEIGHT_WAIT;
            END_IF;

        AT_WEIGHT_WAIT:
            IF weightComplete THEN
                IF (weight >= 100.0) AND (weight <= 200.0) THEN
                    // Qualified material
                    firingTemp := 500.0 + (weight - 100.0) * 0.5;
                    MotorForward := TRUE;
                    currentState := MOVING_WEIGHT_TO_FIRING;
                ELSE
                    // Unqualified material
                    kick := TRUE;
                    currentState := AT_WEIGHT_REJECT;
                END_IF;
            END_IF;

        AT_WEIGHT_REJECT:
            kick := TRUE;
            IF NOT SensorWeight THEN
                kick := FALSE;
                currentState := IDLE;
            END_IF;

        MOVING_WEIGHT_TO_FIRING:
            MotorForward := TRUE;
            IF SensorFiring THEN
                MotorForward := FALSE;
                currentState := AT_FIRING;
            END_IF;

        AT_FIRING:
            IF firingComplete THEN
                MotorForward := TRUE;
                currentState := MOVING_FIRING_TO_OUTPUT;
            END_IF;

        MOVING_FIRING_TO_OUTPUT:
            MotorForward := TRUE;
            IF SensorOutput THEN
                MotorForward := FALSE;
                currentState := AT_OUTPUT;
            END_IF;

        AT_OUTPUT:
            CompletionLight := TRUE;
            IF NOT SensorOutput THEN
                CompletionLight := FALSE;
                currentState := IDLE;
            END_IF;
    END_CASE;
END_IF;

END_FUNCTION_BLOCK