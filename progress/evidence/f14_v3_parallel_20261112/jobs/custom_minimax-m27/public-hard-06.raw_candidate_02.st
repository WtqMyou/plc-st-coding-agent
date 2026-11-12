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
    prodState        : INT;
END_VAR

prodState := State;

kick := FALSE;
firingTemp := 0.0;

prevSensorFeed := SensorFeed;
prevSensorWash := SensorWash;
prevSensorWeight := SensorWeight;
prevSensorFiring := SensorFiring;
prevSensorOutput := SensorOutput;

IF Mode = FALSE THEN
    MotorForward := FALSE;
    MotorReverse := FALSE;
    kick := FALSE;
    CompletionLight := FALSE;
    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
    END_IF;
    IF ReverseButton AND NOT ForwardButton THEN
        MotorReverse := TRUE;
    END_IF;
    State := 0;
ELSE
    CompletionLight := FALSE;
    CASE State OF
        0:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            kick := FALSE;
            IF SensorFeed AND NOT prevSensorFeed THEN
                State := 1;
            END_IF;

        1:
            MotorForward := TRUE;
            MotorReverse := FALSE;
            IF SensorWash AND NOT prevSensorWash THEN
                State := 2;
            END_IF;

        2:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            IF washComplete THEN
                State := 3;
            END_IF;

        3:
            MotorForward := TRUE;
            MotorReverse := FALSE;
            IF SensorWeight AND NOT prevSensorWeight THEN
                State := 4;
            END_IF;

        4:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            IF weightComplete THEN
                State := 5;
            END_IF;

        5:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            IF weight < 100.0 OR weight > 200.0 THEN
                State := 6;
            ELSE
                State := 7;
            END_IF;

        6:
            kick := TRUE;
            MotorForward := FALSE;
            MotorReverse := FALSE;
            State := 0;

        7:
            kick := FALSE;
            firingTemp := 500.0 + ((weight - 100.0) / 100.0) * 50.0;
            State := 8;

        8:
            MotorForward := TRUE;
            MotorReverse := FALSE;
            kick := FALSE;
            IF SensorFiring AND NOT prevSensorFiring THEN
                State := 9;
            END_IF;

        9:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            IF firingComplete THEN
                State := 10;
            END_IF;

        10:
            MotorForward := TRUE;
            MotorReverse := FALSE;
            IF SensorOutput AND NOT prevSensorOutput THEN
                State := 11;
            END_IF;

        11:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            CompletionLight := TRUE;
            IF NOT SensorOutput THEN
                CompletionLight := FALSE;
                firingTemp := 0.0;
                State := 0;
            END_IF;
    END_CASE;
END_IF;
END_FUNCTION_BLOCK