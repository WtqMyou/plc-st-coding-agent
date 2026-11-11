FUNCTION_BLOCK FB
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
    kick            : BOOL;
    CompletionLight : BOOL;
    firingTemp      : REAL;
END_VAR
VAR
    eState          : INT;
    prevMode        : BOOL;
END_VAR

// Initialize outputs
MotorForward    := FALSE;
MotorReverse    := FALSE;
kick            := FALSE;
CompletionLight := FALSE;
firingTemp      := 0.0;

// Manual mode
IF NOT Mode THEN
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
    prevMode := Mode;
    RETURN;
END_IF

// Automatic mode entry detection
IF NOT prevMode THEN
    // Determine initial state based on current product position
    IF SensorFeed THEN
        eState := 0;
    ELSIF SensorWash THEN
        eState := 1;
    ELSIF SensorWeight THEN
        eState := 2;
    ELSIF SensorFiring THEN
        eState := 3;
    ELSIF SensorOutput THEN
        eState := 5;
    END_IF
END_IF
prevMode := Mode;

// State-based motor control
CASE eState OF
    0: // At feed station
        MotorForward := FALSE;
        IF SensorWash THEN
            eState := 1;
        END_IF
        
    1: // At wash station
        MotorForward := FALSE;
        IF washComplete THEN
            eState := 2;
            MotorForward := TRUE;
        END_IF
        
    2: // Moving to weight station
        MotorForward := TRUE;
        IF SensorWeight THEN
            eState := 3;
            MotorForward := FALSE;
        END_IF
        
    3: // At weight station
        MotorForward := FALSE;
        IF weightComplete THEN
            IF weight >= 100.0 AND weight <= 200.0 THEN
                eState := 4;
                firingTemp := 500.0 + (weight - 100.0) * 0.5;
            ELSE
                eState := 6;
                kick := TRUE;
            END_IF
        END_IF
        
    4: // Moving to firing station
        MotorForward := TRUE;
        IF SensorFiring THEN
            eState := 5;
            MotorForward := FALSE;
        END_IF
        
    5: // At firing station
        MotorForward := FALSE;
        IF firingComplete THEN
            eState := 7;
            MotorForward := TRUE;
        END_IF
        
    6: // KICK state
        MotorForward := FALSE;
        IF NOT SensorWeight THEN
            kick := FALSE;
            eState := 0;
        END_IF
        
    7: // Moving to output station
        MotorForward := TRUE;
        IF SensorOutput THEN
            eState := 8;
            MotorForward := FALSE;
        END_IF
        
    8: // At output station
        MotorForward := FALSE;
        CompletionLight := TRUE;
        IF NOT SensorOutput THEN
            eState := 0;
            CompletionLight := FALSE;
        END_IF
        
END_CASE

END_FUNCTION_BLOCK