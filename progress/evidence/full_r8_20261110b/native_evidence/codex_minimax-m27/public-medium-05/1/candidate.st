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
    phase           : INT;  // 0=idle, 1=waitA, 2=AtoB, 3=waitB, 4=BtoC, 5=waitC
    prevMode        : BOOL;
END_VAR

    prevMode := Mode;

    // Mode transitions
    IF NOT Mode THEN
        phase := 0;
    ELSIF prevMode THEN
        // Already in auto, check sensor arrivals
        IF phase = 2 AND SensorB THEN
            phase := 3;
        ELSIF phase = 4 AND SensorC THEN
            phase := 5;
        ELSIF phase = 5 AND NOT SensorC THEN
            phase := 0;
        END_IF
    ELSE
        // Rising edge into auto mode
        IF SensorA AND ButtonA THEN
            phase := 1;
        END_IF
    END_IF;

    // Phase progression
    IF phase = 1 AND NOT ButtonA THEN
        phase := 2;
    ELSIF phase = 3 AND NOT ButtonB THEN
        phase := 4;
    END_IF;

    // Motor outputs
    MotorForward := FALSE;
    MotorReverse := FALSE;

    IF NOT Mode THEN
        // Manual mode with interlock
        IF ForwardButton AND NOT ReverseButton THEN
            MotorForward := TRUE;
        ELSIF ReverseButton AND NOT ForwardButton THEN
            MotorReverse := TRUE;
        END_IF;
    ELSE
        // Automatic mode
        IF phase = 2 THEN
            MotorForward := TRUE;
        ELSIF phase = 4 THEN
            MotorForward := TRUE;
        END_IF;
    END_IF;

    // Completion light
    CompletionLight := FALSE;
    IF Mode AND phase = 5 AND SensorC THEN
        CompletionLight := TRUE;
    END_IF;
END_FUNCTION_BLOCK