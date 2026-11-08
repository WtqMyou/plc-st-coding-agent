TYPE StepEnum :
(
    Idle := 0,
    AtA,
    MovingAB,
    AtB,
    MovingBC,
    AtC
);
END_TYPE

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
    prevMode            : BOOL := FALSE;
    prevForwardButton   : BOOL := FALSE;
    prevReverseButton   : BOOL := FALSE;
    prevButtonA         : BOOL := FALSE;
    prevButtonB         : BOOL := FALSE;
    prevButtonC         : BOOL := FALSE;
    prevSensorA         : BOOL := FALSE;
    prevSensorB         : BOOL := FALSE;
    prevSensorC         : BOOL := FALSE;
    currentStep         : StepEnum := Idle;
    buttonAPressed      : BOOL;
    buttonBPressed      : BOOL;
    buttonCPressed      : BOOL;
    sensorAArrived      : BOOL;
    sensorBArrived      : BOOL;
    sensorCArrived      : BOOL;
    sensorCRemoved      : BOOL;
END_VAR

// Detect mode change
IF Mode <> prevMode THEN
    IF NOT Mode THEN
        currentStep := Idle;
        CompletionLight := FALSE;
    END_IF;
END_IF;

// Compute edge detections
buttonAPressed   := ButtonA AND NOT prevButtonA;
buttonBPressed   := ButtonB AND NOT prevButtonB;
buttonCPressed   := ButtonC AND NOT prevButtonC;
sensorAArrived   := SensorA AND NOT prevSensorA;
sensorBArrived   := SensorB AND NOT prevSensorB;
sensorCArrived   := SensorC AND NOT prevSensorC;
sensorCRemoved   := prevSensorC AND NOT SensorC;

IF Mode = FALSE THEN
    // Manual mode
    MotorForward    := ForwardButton AND NOT ReverseButton;
    MotorReverse    := ReverseButton AND NOT ForwardButton;
    CompletionLight := FALSE;
ELSE
    // Automatic mode
    MotorReverse    := FALSE;
    MotorForward    := FALSE;

    CASE currentStep OF
        Idle:
            IF SensorA THEN
                currentStep := AtA;
            END_IF;

        AtA:
            IF buttonAPressed THEN
                currentStep := MovingAB;
                MotorForward := TRUE;
            END_IF;

        MovingAB:
            MotorForward := TRUE;
            IF sensorBArrived THEN
                MotorForward := FALSE;
                currentStep := AtB;
            END_IF;

        AtB:
            IF buttonBPressed THEN
                currentStep := MovingBC;
                MotorForward := TRUE;
            END_IF;

        MovingBC:
            MotorForward := TRUE;
            IF sensorCArrived THEN
                MotorForward := FALSE;
                currentStep := AtC;
            END_IF;

        AtC:
            IF buttonCPressed THEN
                CompletionLight := TRUE;
            END_IF;
            IF sensorCRemoved THEN
                CompletionLight := FALSE;
                currentStep := Idle;
            END_IF;
    END_CASE;
END_IF;

// Update previous inputs for next scan
prevMode            := Mode;
prevForwardButton   := ForwardButton;
prevReverseButton   := ReverseButton;
prevButtonA         := ButtonA;
prevButtonB         := ButtonB;
prevButtonC         := ButtonC;
prevSensorA         := SensorA;
prevSensorB         := SensorB;
prevSensorC         := SensorC;

END_FUNCTION_BLOCK