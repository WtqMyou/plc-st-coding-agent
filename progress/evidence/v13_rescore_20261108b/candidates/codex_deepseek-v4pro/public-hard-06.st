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
    AutoState : INT := 0;
    washPrev : BOOL;
    weightPrev : BOOL;
    firingPrev : BOOL;
    washRising : BOOL;
    weightRising : BOOL;
    firingRising : BOOL;
    tempCalc : REAL := 0.0;
END_VAR

washRising := washComplete AND NOT washPrev;
weightRising := weightComplete AND NOT weightPrev;
firingRising := firingComplete AND NOT firingPrev;

kick := FALSE;

IF Mode THEN
    CASE AutoState OF
        0:
            IF SensorOutput THEN
                AutoState := 8;
            ELSIF SensorFiring THEN
                AutoState := 6;
            ELSIF SensorWeight THEN
                AutoState := 4;
            ELSIF SensorWash THEN
                AutoState := 2;
            ELSIF SensorFeed THEN
                AutoState := 1;
            END_IF;

        1:
            IF SensorWash THEN
                AutoState := 2;
            END_IF;

        2:
            IF washRising THEN
                AutoState := 3;
            END_IF;

        3:
            IF SensorWeight THEN
                AutoState := 4;
            END_IF;

        4:
            IF NOT SensorWeight THEN
                AutoState := 0;
            ELSIF weightRising THEN
                IF (weight >= 100.0) AND (weight <= 200.0) THEN
                    tempCalc := 500.0 + (weight - 100.0) * 0.5;
                    AutoState := 5;
                ELSE
                    tempCalc := 0.0;
                END_IF;
            END_IF;

        5:
            IF SensorFiring THEN
                AutoState := 6;
            END_IF;

        6:
            IF firingRising THEN
                AutoState := 7;
            END_IF;

        7:
            IF SensorOutput THEN
                AutoState := 8;
            END_IF;

        8:
            IF NOT SensorOutput THEN
                AutoState := 0;
            END_IF;
    END_CASE;

    IF (AutoState = 4) AND weightRising AND ((weight < 100.0) OR (weight > 200.0)) THEN
        kick := TRUE;
    END_IF;

    MotorForward := (AutoState = 1) OR (AutoState = 3) OR (AutoState = 5) OR (AutoState = 7);
    MotorReverse := FALSE;
ELSE
    AutoState := 0;
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
END_IF

washPrev := washComplete;
weightPrev := weightComplete;
firingPrev := firingComplete;

CompletionLight := SensorOutput;
firingTemp := tempCalc;