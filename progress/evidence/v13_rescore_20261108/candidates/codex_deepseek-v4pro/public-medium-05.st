FUNCTION_BLOCK FB
VAR_INPUT
    Mode : BOOL;
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
    ButtonA_Prev : BOOL;
    ButtonB_Prev : BOOL;
    ButtonC_Prev : BOOL;
    ButtonA_Rising : BOOL;
    ButtonB_Rising : BOOL;
    ButtonC_Rising : BOOL;
    MovingAB : BOOL;
    MovingBC : BOOL;
    WorkComplete : BOOL;
END_VAR

MotorForward := FALSE;
MotorReverse := FALSE;
CompletionLight := FALSE;

ButtonA_Rising := ButtonA AND NOT ButtonA_Prev;
ButtonB_Rising := ButtonB AND NOT ButtonB_Prev;
ButtonC_Rising := ButtonC AND NOT ButtonC_Prev;

IF NOT Mode THEN
    MovingAB := FALSE;
    MovingBC := FALSE;
    WorkComplete := FALSE;

    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
    END_IF;

    IF ReverseButton AND NOT ForwardButton THEN
        MotorReverse := TRUE;
    END_IF;
ELSE
    IF SensorB AND MovingAB THEN
        MovingAB := FALSE;
    END_IF;

    IF SensorC AND MovingBC THEN
        MovingBC := FALSE;
    END_IF;

    IF NOT SensorC THEN
        WorkComplete := FALSE;
    END_IF;

    IF SensorA AND ButtonA_Rising AND NOT MovingAB AND NOT MovingBC THEN
        MovingAB := TRUE;
    END_IF;

    IF SensorB AND ButtonB_Rising AND NOT MovingBC THEN
        MovingBC := TRUE;
    END_IF;

    IF SensorC AND ButtonC_Rising THEN
        WorkComplete := TRUE;
    END_IF;

    MotorForward := MovingAB OR MovingBC;
    CompletionLight := SensorC AND WorkComplete;
END_IF;

ButtonA_Prev := ButtonA;
ButtonB_Prev := ButtonB;
ButtonC_Prev := ButtonC;
END_FUNCTION_BLOCK