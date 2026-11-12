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
VAR CONSTANT
    ST_IDLE : INT := 0;
    ST_MOVE_WASH : INT := 1;
    ST_AT_WASH : INT := 2;
    ST_MOVE_WEIGHT : INT := 3;
    ST_AT_WEIGHT : INT := 4;
    ST_REJECTED : INT := 5;
    ST_MOVE_FIRING : INT := 6;
    ST_AT_FIRING : INT := 7;
    ST_MOVE_OUTPUT : INT := 8;
    ST_AT_OUTPUT : INT := 9;
END_VAR
VAR
    state : INT := 0;
END_VAR

MotorForward := FALSE;
MotorReverse := FALSE;
kick := FALSE;
CompletionLight := FALSE;

IF NOT Mode THEN
    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
    ELSIF ReverseButton AND NOT ForwardButton THEN
        MotorReverse := TRUE;
    END_IF;
    firingTemp := 0.0;
ELSE
    CASE state OF
        ST_IDLE:
            IF SensorFeed THEN
                MotorForward := TRUE;
                state := ST_MOVE_WASH;
            END_IF;

        ST_MOVE_WASH:
            MotorForward := TRUE;
            IF SensorWash THEN
                MotorForward := FALSE;
                state := ST_AT_WASH;
            END_IF;

        ST_AT_WASH:
            IF washComplete THEN
                MotorForward := TRUE;
                state := ST_MOVE_WEIGHT;
            END_IF;

        ST_MOVE_WEIGHT:
            MotorForward := TRUE;
            IF SensorWeight THEN
                MotorForward := FALSE;
                state := ST_AT_WEIGHT;
            END_IF;

        ST_AT_WEIGHT:
            IF weightComplete THEN
                IF (weight >= 100.0) AND (weight <= 200.0) THEN
                    firingTemp := 500.0 + ((weight - 100.0) * 50.0) / 100.0;
                    MotorForward := TRUE;
                    state := ST_MOVE_FIRING;
                ELSE
                    kick := TRUE;
                    state := ST_REJECTED;
                END_IF;
            END_IF;

        ST_REJECTED:
            kick := TRUE;
            IF NOT SensorWeight THEN
                kick := FALSE;
                state := ST_IDLE;
            END_IF;

        ST_MOVE_FIRING:
            MotorForward := TRUE;
            IF SensorFiring THEN
                MotorForward := FALSE;
                state := ST_AT_FIRING;
            END_IF;

        ST_AT_FIRING:
            IF firingComplete THEN
                MotorForward := TRUE;
                state := ST_MOVE_OUTPUT;
            END_IF;

        ST_MOVE_OUTPUT:
            MotorForward := TRUE;
            IF SensorOutput THEN
                MotorForward := FALSE;
                CompletionLight := TRUE;
                state := ST_AT_OUTPUT;
            END_IF;

        ST_AT_OUTPUT:
            CompletionLight := TRUE;
            IF NOT SensorOutput THEN
                CompletionLight := FALSE;
                state := ST_IDLE;
            END_IF;
    END_CASE;
END_IF;

END_FUNCTION_BLOCK