FUNCTION_BLOCK FB
VAR_INPUT
    Mode            : BOOL;
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
VAR
    State           : INT := 0;
    prevSensorA     : BOOL := FALSE;
    prevSensorB     : BOOL := FALSE;
    prevSensorC     : BOOL := FALSE;
    prevButtonA     : BOOL := FALSE;
    prevButtonB     : BOOL := FALSE;
    prevButtonC     : BOOL := FALSE;
    SensorARising   : BOOL;
    SensorBRising   : BOOL;
    SensorCRising   : BOOL;
    ButtonARising   : BOOL;
    ButtonBRising   : BOOL;
    ButtonCRising   : BOOL;
END_VAR

// Edge detection
ButtonARising := ButtonA AND NOT prevButtonA;
ButtonBRising := ButtonB AND NOT prevButtonB;
ButtonCRising := ButtonC AND NOT prevButtonC;
SensorARising := SensorA AND NOT prevSensorA;
SensorBRising := SensorB AND NOT prevSensorB;
SensorCRising := SensorC AND NOT prevSensorC;

// Update history
prevButtonA := ButtonA;
prevButtonB := ButtonB;
prevButtonC := ButtonC;
prevSensorA := SensorA;
prevSensorB := SensorB;
prevSensorC := SensorC;

// Initialize outputs
MotorForward    := FALSE;
MotorReverse    := FALSE;
CompletionLight := FALSE;

// Automatic mode state machine
IF Mode THEN
    CASE State OF
        0: // IDLE
            IF SensorARising THEN
                State := 1;
            END_IF

        1: // WAIT_A
            MotorForward := FALSE;
            IF ButtonARising THEN
                State := 2;
            END_IF

        2: // Moving A->B
            MotorForward := TRUE;
            IF SensorBRising THEN
                State := 3;
            END_IF

        3: // WAIT_B
            MotorForward := FALSE;
            IF ButtonBRising THEN
                State := 4;
            END_IF

        4: // Moving B->C
            MotorForward := TRUE;
            IF SensorCRising THEN
                State := 5;
            END_IF

        5: // WAIT_C
            MotorForward := FALSE;
            CompletionLight := SensorC;
            IF NOT SensorC THEN
                State := 0;
            END_IF
    END_CASE
ELSE
    // Manual mode: reset state and handle interlocked control
    State := 0;

    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
    ELSIF ReverseButton AND NOT ForwardButton THEN
        MotorReverse := TRUE;
    END_IF
END_IF
END_FUNCTION_BLOCK