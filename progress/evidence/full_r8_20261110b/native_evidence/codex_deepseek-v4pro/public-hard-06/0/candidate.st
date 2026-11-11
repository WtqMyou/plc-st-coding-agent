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
    nextState : INT := 0;
    autoForwardCmd : BOOL := FALSE;
    manualForwardCmd : BOOL := FALSE;
    manualReverseCmd : BOOL := FALSE;
    tempValue : REAL := 0.0;
END_VAR

kick := FALSE;
CompletionLight := FALSE;
autoForwardCmd := FALSE;
manualForwardCmd := FALSE;
manualReverseCmd := FALSE;
nextState := state;

IF Mode THEN
    CASE state OF
        0:
            IF SensorFeed THEN
                autoForwardCmd := TRUE;
                nextState := 1;
            END_IF;
        1:
            IF SensorWash THEN
                nextState := 2;
            ELSE
                autoForwardCmd := TRUE;
            END_IF;
        2:
            IF washComplete THEN
                autoForwardCmd := TRUE;
                nextState := 3;
            END_IF;
        3:
            IF SensorWeight THEN
                nextState := 4;
            ELSE
                autoForwardCmd := TRUE;
            END_IF;
        4:
            IF weightComplete THEN
                IF (weight >= 100.0) AND (weight <= 200.0) THEN
                    tempValue := 500.0 + (weight - 100.0) * 0.5;
                    autoForwardCmd := TRUE;
                    nextState := 5;
                ELSE
                    kick := TRUE;
                    nextState := 0;
                END_IF;
            END_IF;
        5:
            IF SensorFiring THEN
                nextState := 6;
            ELSE
                autoForwardCmd := TRUE;
            END_IF;
        6:
            IF firingComplete THEN
                autoForwardCmd := TRUE;
                nextState := 7;
            END_IF;
        7:
            IF SensorOutput THEN
                CompletionLight := TRUE;
                nextState := 8;
            ELSE
                autoForwardCmd := TRUE;
            END_IF;
        8:
            IF SensorOutput THEN
                CompletionLight := TRUE;
            ELSE
                nextState := 0;
            END_IF;
    END_CASE;
    state := nextState;
ELSE
    manualForwardCmd := ForwardButton AND NOT ReverseButton;
    manualReverseCmd := ReverseButton AND NOT ForwardButton;
END_IF;

MotorForward := autoForwardCmd OR manualForwardCmd;
MotorReverse := manualReverseCmd;
firingTemp := tempValue;

END_FUNCTION_BLOCK