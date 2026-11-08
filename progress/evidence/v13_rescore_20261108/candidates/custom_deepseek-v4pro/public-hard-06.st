FUNCTION_BLOCK FB
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
VAR
    state : INT := 0;
END_VAR

IF Mode THEN
    (* Automatic mode *)
    MotorReverse := FALSE;
    kick := FALSE;
    CompletionLight := FALSE;
    
    CASE state OF
        0: (* IDLE *)
            IF SensorFeed THEN
                state := 1;
            END_IF
        1: (* MOVING_TO_WASH *)
            IF SensorWash THEN
                state := 2;
            END_IF
        2: (* AT_WASH *)
            IF washComplete THEN
                state := 3;
            END_IF
        3: (* MOVING_TO_WEIGHT *)
            IF SensorWeight THEN
                state := 4;
            END_IF
        4: (* AT_WEIGHT *)
            IF weightComplete THEN
                IF weight >= 100.0 AND weight <= 200.0 THEN
                    firingTemp := 500.0 + (weight - 100.0) * (550.0 - 500.0) / (200.0 - 100.0);
                    state := 5;
                ELSE
                    kick := TRUE;
                    state := 9;
                END_IF
            END_IF
        5: (* MOVING_TO_FIRING *)
            IF SensorFiring THEN
                state := 6;
            END_IF
        6: (* AT_FIRING *)
            IF firingComplete THEN
                state := 7;
            END_IF
        7: (* MOVING_TO_OUTPUT *)
            IF SensorOutput THEN
                state := 8;
            END_IF
        8: (* AT_OUTPUT *)
            CompletionLight := TRUE;
            IF NOT SensorOutput THEN
                CompletionLight := FALSE;
                state := 0;
            END_IF
        9: (* REJECTING *)
            IF NOT SensorWeight THEN
                state := 0;
            END_IF
    END_CASE
    
    IF state = 1 OR state = 3 OR state = 5 OR state = 7 THEN
        MotorForward := TRUE;
    ELSE
        MotorForward := FALSE;
    END_IF

ELSE
    (* Manual mode *)
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
    kick := FALSE;
    CompletionLight := FALSE;
    state := 0;
END_IF

END_FUNCTION_BLOCK