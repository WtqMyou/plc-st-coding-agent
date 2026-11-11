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
    MotorForward : BOOL;
    MotorReverse : BOOL;
    kick : BOOL;
    CompletionLight : BOOL;
    firingTemp : REAL;
END_VAR
VAR
    AutoState : INT := 0;
    autoMotorForward : BOOL;
    autoMotorReverse : BOOL;
    autoKick : BOOL;
    autoCompletionLight : BOOL;
    autoFiringTemp : REAL := 0.0;
END_VAR

IF Mode THEN
    (* Automatic mode *)
    autoMotorForward := FALSE;
    autoMotorReverse := FALSE;
    autoKick := FALSE;
    autoCompletionLight := FALSE;

    CASE AutoState OF
        0: (* Idle *)
            IF SensorFeed AND NOT SensorWash THEN
                AutoState := 1;
                autoMotorForward := TRUE;
            END_IF;

        1: (* Moving from feed to wash *)
            autoMotorForward := TRUE;
            IF SensorWash THEN
                AutoState := 2;
                autoMotorForward := FALSE;
            END_IF;

        2: (* At wash waiting for washComplete *)
            autoMotorForward := FALSE;
            IF washComplete THEN
                AutoState := 3;
                autoMotorForward := TRUE;
            END_IF;

        3: (* Moving from wash to weight *)
            autoMotorForward := TRUE;
            IF SensorWeight THEN
                AutoState := 4;
                autoMotorForward := FALSE;
            END_IF;

        4: (* At weight waiting for weightComplete *)
            autoMotorForward := FALSE;
            IF weightComplete THEN
                IF (weight >= 100.0) AND (weight <= 200.0) THEN
                    autoFiringTemp := 500.0 + (weight - 100.0) * 0.5;
                    AutoState := 5;
                    autoMotorForward := TRUE;
                ELSE
                    autoKick := TRUE;
                    AutoState := 0; (* Reject and return to idle *)
                END_IF;
            END_IF;

        5: (* Moving from weight to firing *)
            autoMotorForward := TRUE;
            IF SensorFiring THEN
                AutoState := 6;
                autoMotorForward := FALSE;
            END_IF;

        6: (* At firing waiting for firingComplete *)
            autoMotorForward := FALSE;
            IF firingComplete THEN
                AutoState := 7;
                autoMotorForward := TRUE;
            END_IF;

        7: (* Moving from firing to output *)
            autoMotorForward := TRUE;
            IF SensorOutput THEN
                AutoState := 8;
                autoMotorForward := FALSE;
                autoCompletionLight := TRUE;
            END_IF;

        8: (* At finished product station *)
            autoMotorForward := FALSE;
            autoCompletionLight := TRUE;
            IF NOT SensorOutput THEN
                AutoState := 0;
                autoCompletionLight := FALSE;
            END_IF;
    END_CASE;

    MotorForward := autoMotorForward;
    MotorReverse := autoMotorReverse;
    kick := autoKick;
    CompletionLight := autoCompletionLight;
    firingTemp := autoFiringTemp;
ELSE
    (* Manual mode *)
    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
        MotorReverse := FALSE;
    ELSIF ReverseButton AND NOT ForwardButton THEN
        MotorForward := FALSE;
        MotorReverse := TRUE;
    ELSE
        MotorForward := FALSE;
        MotorReverse := FALSE;
    END_IF;
    kick := FALSE;
    CompletionLight := FALSE;
    firingTemp := 0.0;
END_IF;

END_FUNCTION_BLOCK