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
    phase           : INT;  // 0=idle, 1=atA, 2=AB, 3=atB, 4=BC, 5=atC
    prevMode        : BOOL;
    prevSensorC     : BOOL;
    prevCompletionLight : BOOL;
END_VAR

    prevMode := Mode;
    prevSensorC := SensorC;
    prevCompletionLight := CompletionLight;

    IF phase = 0 THEN
        MotorForward := FALSE;
        IF Mode AND SensorA AND ButtonA THEN
            phase := 2;
        END_IF
    ELSIF phase = 1 THEN
        MotorForward := FALSE;
        IF ButtonA THEN
            phase := 2;
        END_IF
    ELSIF phase = 2 THEN
        MotorForward := TRUE;
        IF SensorB THEN
            MotorForward := FALSE;
            phase := 3;
        END_IF
    ELSIF phase = 3 THEN
        MotorForward := FALSE;
        IF ButtonB THEN
            phase := 4;
        END_IF
    ELSIF phase = 4 THEN
        MotorForward := TRUE;
        IF SensorC THEN
            MotorForward := FALSE;
            phase := 5;
        END_IF
    ELSIF phase = 5 THEN
        MotorForward := FALSE;
        CompletionLight := Mode AND SensorC AND ButtonC;
        IF NOT SensorC THEN
            CompletionLight := FALSE;
            phase := 0;
        END_IF
    END_IF

    MotorReverse := FALSE;
    IF NOT Mode THEN
        IF ForwardButton AND NOT ReverseButton THEN
            MotorForward := TRUE;
        ELSIF ReverseButton AND NOT ForwardButton THEN
            MotorReverse := TRUE;
        ELSE
            MotorForward := FALSE;
        END_IF
        IF prevMode THEN
            phase := 0;
        END_IF
    END_IF
END_FUNCTION_BLOCK