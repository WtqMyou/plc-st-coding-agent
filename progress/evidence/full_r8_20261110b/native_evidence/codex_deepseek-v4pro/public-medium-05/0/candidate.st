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
    AutoState : INT := 0;
    AutoForward : BOOL;
    ManualForward : BOOL;
    ManualReverse : BOOL;
    PrevMode : BOOL;
    PrevMotorForward : BOOL;
    PrevCompletionLight : BOOL;
END_VAR

IF Mode THEN
    ManualForward := FALSE;
    ManualReverse := FALSE;

    CASE AutoState OF
        0:
            IF SensorA AND ButtonA THEN
                AutoState := 1;
                AutoForward := TRUE;
            ELSE
                AutoForward := FALSE;
            END_IF

        1:
            AutoForward := TRUE;
            IF SensorB THEN
                AutoState := 2;
                AutoForward := FALSE;
            END_IF

        2:
            AutoForward := FALSE;
            IF SensorB AND ButtonB THEN
                AutoState := 3;
                AutoForward := TRUE;
            END_IF

        3:
            AutoForward := TRUE;
            IF SensorC THEN
                AutoState := 4;
                AutoForward := FALSE;
            END_IF

        4:
            AutoForward := FALSE;
    END_CASE
ELSE
    AutoState := 0;
    AutoForward := FALSE;
    ManualForward := ForwardButton AND NOT ReverseButton;
    ManualReverse := ReverseButton AND NOT ForwardButton;
END_IF

MotorForward := AutoForward OR ManualForward;
MotorReverse := ManualReverse AND NOT Mode AND NOT MotorForward;

CompletionLight := Mode AND SensorC AND (PrevCompletionLight OR ButtonC);

PrevMode := Mode;
PrevMotorForward := MotorForward;
PrevCompletionLight := CompletionLight;

END_FUNCTION_BLOCK