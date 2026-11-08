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
    eState              : INT;
    prevForwardButton   : BOOL;
    prevReverseButton   : BOOL;
    prevwashComplete    : BOOL;
    prevweightComplete  : BOOL;
    prevfiringComplete  : BOOL;
    bKickDone           : BOOL;
END_VAR

    // Edge detection: rising edge flags
    VAR
        bFwdRising   : BOOL;
        bRevRising   : BOOL;
        bWashRising  : BOOL;
        bWeightRising: BOOL;
        bFiringRising: BOOL;
    END_VAR

    bFwdRising   := (NOT prevForwardButton)  AND ForwardButton;
    bRevRising   := (NOT prevReverseButton)  AND ReverseButton;
    bWashRising  := (NOT prevwashComplete)   AND washComplete;
    bWeightRising:= (NOT prevweightComplete) AND weightComplete;
    bFiringRising:= (NOT prevfiringComplete) AND firingComplete;

    // Reset kick flag on new cycle start (ForwardButton rising edge in any mode)
    IF bFwdRising THEN
        bKickDone := FALSE;
    END_IF

    IF Mode = FALSE THEN
        // Manual mode
        eState := 0;
        MotorForward := ForwardButton;
        MotorReverse := ReverseButton;
        kick := FALSE;
        CompletionLight := FALSE;
        firingTemp := 0.0;
    ELSE
        // Automatic mode
        CASE eState OF
            0:  // IDLE
                MotorForward := FALSE;
                MotorReverse := FALSE;
                kick := FALSE;
                CompletionLight := FALSE;
                firingTemp := 0.0;
                bKickDone := FALSE;
                IF SensorFeed THEN
                    eState := 1;
                END_IF

            1:  // MOVING_TO_WASH
                MotorForward := TRUE;
                MotorReverse := FALSE;
                kick := FALSE;
                IF SensorWash THEN
                    eState := 2;
                END_IF

            2:  // AT_WASH
                MotorForward := FALSE;
                MotorReverse := FALSE;
                kick := FALSE;
                IF bWashRising THEN
                    eState := 3;
                END_IF

            3:  // MOVING_TO_WEIGH
                MotorForward := TRUE;
                MotorReverse := FALSE;
                kick := FALSE;
                IF SensorWeight THEN
                    eState := 4;
                END_IF

            4:  // AT_WEIGH
                MotorForward := FALSE;
                MotorReverse := FALSE;
                kick := FALSE;
                IF bWeightRising THEN
                    IF weight >= 100.0 AND weight <= 200.0 THEN
                        firingTemp := 500.0 + (weight - 100.0) * 0.5;
                        eState := 6;
                    ELSE
                        eState := 5;
                    END_IF;
                END_IF

            5:  // KICKING
                MotorForward := FALSE;
                MotorReverse := FALSE;
                kick := TRUE;
                IF NOT bKickDone THEN
                    bKickDone := TRUE;
                    eState := 0;
                END_IF

            6:  // MOVING_TO_FIRING
                MotorForward := TRUE;
                MotorReverse := FALSE;
                kick := FALSE;
                IF SensorFiring THEN
                    eState := 7;
                END_IF

            7:  // AT_FIRING
                MotorForward := FALSE;
                MotorReverse := FALSE;
                kick := FALSE;
                IF bFiringRising THEN
                    eState := 8;
                END_IF

            8:  // MOVING_TO_OUTPUT
                MotorForward := TRUE;
                MotorReverse := FALSE;
                kick := FALSE;
                IF SensorOutput THEN
                    eState := 9;
                END_IF

            9:  // AT_OUTPUT
                MotorForward := FALSE;
                MotorReverse := FALSE;
                kick := FALSE;
                CompletionLight := SensorOutput;
                IF NOT SensorOutput THEN
                    eState := 0;
                END_IF

        END_CASE
    END_IF

    prevForwardButton  := ForwardButton;
    prevReverseButton  := ReverseButton;
    prevwashComplete   := washComplete;
    prevweightComplete := weightComplete;
    prevfiringComplete := firingComplete;

END_FUNCTION_BLOCK