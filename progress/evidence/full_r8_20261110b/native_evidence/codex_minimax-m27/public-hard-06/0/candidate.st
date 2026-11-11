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

// State constants
// FEED_ARRIVED = 0
// WASH_ARRIVED = 1
// WEIGHT_ARRIVED = 2
// WEIGHT_OK = 3
// KICK = 4
// FIRING_ARRIVED = 5
// OUTPUT_ARRIVED = 6

// Initialize outputs to safe state
MotorForward    := FALSE;
MotorReverse    := FALSE;
kick            := FALSE;
firingTemp      := 0.0;
CompletionLight := FALSE;

// Automatic mode
IF Mode THEN
    CASE eState OF
        0: // FEED_ARRIVED
            IF SensorFeed THEN
                eState := 1; // Move to WASH_ARRIVED
                MotorForward := TRUE;
            END_IF
            
        1: // WASH_ARRIVED
            IF SensorWeight THEN
                eState := 2; // Move to WEIGHT_ARRIVED
                MotorForward := FALSE;
            END_IF
            
        2: // WEIGHT_ARRIVED
            IF weightComplete THEN
                IF weight >= 100.0 AND weight <= 200.0 THEN
                    eState := 3; // WEIGHT_OK
                    firingTemp := 500.0 + (weight - 100.0) * 0.5;
                ELSE
                    eState := 4; // KICK
                    kick := TRUE;
                END_IF
                MotorForward := FALSE;
            END_IF
            
        3: // WEIGHT_OK
            IF SensorFiring THEN
                eState := 5; // Move to FIRING_ARRIVED
                MotorForward := FALSE;
            END_IF
            
        4: // KICK
            IF NOT SensorWeight AND SensorFeed THEN
                eState := 0; // Return to FEED_ARRIVED
                kick := FALSE;
                MotorForward := TRUE;
            END_IF
            
        5: // FIRING_ARRIVED
            IF firingComplete THEN
                eState := 6; // Move to OUTPUT_ARRIVED
                MotorForward := TRUE;
            END_IF
            
        6: // OUTPUT_ARRIVED
            CompletionLight := TRUE;
            IF NOT SensorOutput THEN
                eState := 0; // Return to FEED_ARRIVED
                CompletionLight := FALSE;
            END_IF
    END_CASE
    
// Manual mode
ELSE
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
    IF prevMode <> Mode THEN
        eState := 0;
    END_IF
END_IF

prevMode := Mode;
END_FUNCTION_BLOCK