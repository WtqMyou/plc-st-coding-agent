TYPE ProductState : (
    Idle := 0,
    AtFeed := 1,
    AtWash := 2,
    AtWeight := 3,
    AtFiring := 4,
    AtOutput := 5,
    Rejected := 6
);
END_TYPE;

TYPE ModeType : (Manual := 0, Auto := 1, Sequence := 2);
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
    MotorForward : BOOL := FALSE;
    MotorReverse : BOOL := FALSE;
    kick : BOOL := FALSE;
    CompletionLight : BOOL := FALSE;
    firingTemp : REAL := 0.0;
END_VAR

VAR
    currentState : ProductState := Idle;
    prevSensorFeed : BOOL := FALSE;
    prevSensorWash : BOOL := FALSE;
    prevSensorWeight : BOOL := FALSE;
    prevSensorFiring : BOOL := FALSE;
    prevSensorOutput : BOOL := FALSE;
    prevWashComplete : BOOL := FALSE;
    prevWeightComplete : BOOL := FALSE;
    prevFiringComplete : BOOL := FALSE;
END_VAR

IF currentState = Idle THEN
    MotorForward := FALSE;
    MotorReverse := FALSE;
    kick := FALSE;
    CompletionLight := FALSE;
    firingTemp := 0.0;
END_IF;

IF Mode = FALSE THEN
    MotorForward := ForwardButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
ELSE
    MotorReverse := FALSE;
    
    IF currentState = Idle THEN
        IF SensorFeed AND NOT prevSensorFeed THEN
            currentState := AtFeed;
            MotorForward := TRUE;
        END_IF;
        
    ELSIF currentState = AtFeed THEN
        MotorForward := TRUE;
        IF SensorWash AND NOT prevSensorWash THEN
            currentState := AtWash;
            MotorForward := FALSE;
        END_IF;
        
    ELSIF currentState = AtWash THEN
        MotorForward := FALSE;
        IF washComplete AND NOT prevWashComplete THEN
            currentState := AtWeight;
            MotorForward := TRUE;
        END_IF;
        
    ELSIF currentState = AtWeight THEN
        MotorForward := FALSE;
        IF weightComplete AND NOT prevWeightComplete THEN
            IF weight < 100.0 OR weight > 200.0 THEN
                kick := TRUE;
                currentState := Rejected;
            ELSE
                firingTemp := 500.0 + (weight - 100.0) * 0.5;
                currentState := AtFiring;
            END_IF;
        END_IF;
        
    ELSIF currentState = AtFiring THEN
        MotorForward := FALSE;
        IF firingComplete AND NOT prevFiringComplete THEN
            currentState := AtOutput;
            CompletionLight := TRUE;
        END_IF;
        
    ELSIF currentState = AtOutput THEN
        MotorForward := FALSE;
        CompletionLight := SensorOutput;
        IF NOT SensorOutput AND prevSensorOutput THEN
            currentState := Idle;
            CompletionLight := FALSE;
        END_IF;
        
    ELSIF currentState = Rejected THEN
        MotorForward := FALSE;
        kick := SensorWeight;
        IF NOT SensorWeight AND prevSensorWeight THEN
            currentState := Idle;
            kick := FALSE;
        END_IF;
        
    END_IF;
END_IF;

prevSensorFeed := SensorFeed;
prevSensorWash := SensorWash;
prevSensorWeight := SensorWeight;
prevSensorFiring := SensorFiring;
prevSensorOutput := SensorOutput;
prevWashComplete := washComplete;
prevWeightComplete := weightComplete;
prevFiringComplete := firingComplete;

END_FUNCTION_BLOCK