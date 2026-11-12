FUNCTION_BLOCK ProductionControl
VAR_INPUT
    Mode            : BOOL;
    ForwardButton   : BOOL;
    ReverseButton   : BOOL;
    SensorFeed      : BOOL;
    SensorWash      : BOOL;
    SensorWeight    : BOOL;
    SensorFiring    : BOOL;
    SensorOutput    : BOOL;
    washComplete    : BOOL;
    weightComplete  : BOOL;
    weight          : REAL;
    firingComplete  : BOOL;
END_VAR

VAR_OUTPUT
    MotorForward    : BOOL;
    MotorReverse    : BOOL;
    kick             : BOOL;
    CompletionLight  : BOOL;
    firingTemp       : REAL;
END_VAR

VAR
    State           : INT;
    prevSensorFeed  : BOOL;
    prevSensorWash  : BOOL;
    prevSensorWeight: BOOL;
    prevSensorFiring: BOOL;
    prevSensorOutput: BOOL;
END_VAR

TYPE ProductionState : INT (
    IDLE            := 0,
    MOVING_TO_WASH  := 1,
    AT_WASH         := 2,
    MOVING_TO_WEIGH := 3,
    AT_WEIGH        := 4,
    QUALITY_CHECK   := 5,
    KICKING         := 6,
    CALCULATING_TEMP:= 7,
    MOVING_TO_FIRING:= 8,
    AT_FIRING       := 9,
    MOVING_TO_OUTPUT:= 10,
    AT_OUTPUT       := 11
);
END_TYPE

// Edge detection helpers
prevSensorFeed  := SensorFeed;
prevSensorWash  := SensorWash;
prevSensorWeight:= SensorWeight;
prevSensorFiring:= SensorFiring;
prevSensorOutput:= SensorOutput;

// Default outputs
MotorForward    := FALSE;
MotorReverse    := FALSE;
kick             := FALSE;
CompletionLight  := FALSE;
firingTemp       := 0.0;

IF Mode = FALSE THEN
    // Manual Mode
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
    State := IDLE;
ELSE
    // Automatic Mode
    CASE State OF
        IDLE:
            IF SensorFeed AND NOT prevSensorFeed THEN
                State := MOVING_TO_WASH;
                MotorForward := TRUE;
            END_IF;

        MOVING_TO_WASH:
            IF SensorWash AND NOT prevSensorWash THEN
                State := AT_WASH;
                MotorForward := FALSE;
            END_IF;

        AT_WASH:
            IF washComplete THEN
                State := MOVING_TO_WEIGH;
                MotorForward := TRUE;
            END_IF;

        MOVING_TO_WEIGH:
            IF SensorWeight AND NOT prevSensorWeight THEN
                State := AT_WEIGH;
                MotorForward := FALSE;
            END_IF;

        AT_WEIGH:
            IF weightComplete THEN
                State := QUALITY_CHECK;
            END_IF;

        QUALITY_CHECK:
            IF weight < 100.0 OR weight > 200.0 THEN
                State := KICKING;
            ELSE
                State := CALCULATING_TEMP;
            END_IF;

        KICKING:
            kick := TRUE;
            State := IDLE;

        CALCULATING_TEMP:
            firingTemp := 500.0 + ((weight - 100.0) / 100.0) * 50.0;
            State := MOVING_TO_FIRING;
            MotorForward := TRUE;

        MOVING_TO_FIRING:
            IF SensorFiring AND NOT prevSensorFiring THEN
                State := AT_FIRING;
                MotorForward := FALSE;
            END_IF;

        AT_FIRING:
            IF firingComplete THEN
                State := MOVING_TO_OUTPUT;
                MotorForward := TRUE;
            END_IF;

        MOVING_TO_OUTPUT:
            IF SensorOutput AND NOT prevSensorOutput THEN
                State := AT_OUTPUT;
                MotorForward := FALSE;
            END_IF;

        AT_OUTPUT:
            CompletionLight := SensorOutput;
            IF NOT SensorOutput THEN
                State := IDLE;
                firingTemp := 0.0;
            END_IF;
    END_CASE;
END_IF;
END_FUNCTION_BLOCK