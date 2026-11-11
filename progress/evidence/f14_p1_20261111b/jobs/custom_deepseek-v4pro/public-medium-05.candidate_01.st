FUNCTION_BLOCK AutomatedProductionLine
VAR_INPUT
    Mode : BOOL;           // 0=Manual, 1=Automatic
    ForwardButton : BOOL;
    ReverseButton : BOOL;
    SensorA : BOOL;
    SensorB : BOOL;
    SensorC : BOOL;
    ButtonA : BOOL;
    ButtonB : BOOL;
    ButtonC : BOOL;
END_VAR
VAR_OUTPUT
    MotorForward : BOOL;
    MotorReverse : BOOL;
    CompletionLight : BOOL;
END_VAR
VAR
    MoveAB : BOOL := FALSE;  // A -> B transport active
    MoveBC : BOOL := FALSE;  // B -> C transport active
END_VAR

IF Mode THEN
    // ----- Automatic mode -----
    MotorReverse := FALSE;

    // A to B transport
    IF SensorA AND ButtonA THEN
        MoveAB := TRUE;
    ELSIF SensorB THEN
        MoveAB := FALSE;
    END_IF;

    // B to C transport
    IF SensorB AND ButtonB THEN
        MoveBC := TRUE;
    ELSIF SensorC THEN
        MoveBC := FALSE;
    END_IF;

    // Motor forward runs while either transport is active
    MotorForward := MoveAB OR MoveBC;

    // Completion light logic
    IF SensorC THEN
        IF ButtonC THEN
            CompletionLight := TRUE;
        END_IF;
    ELSE
        CompletionLight := FALSE;
    END_IF;

ELSE
    // ----- Manual mode -----
    // Reset automatic state
    MoveAB := FALSE;
    MoveBC := FALSE;
    CompletionLight := FALSE;

    // Forward and reverse with mutual interlock
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
END_IF;