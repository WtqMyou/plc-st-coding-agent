FUNCTION_BLOCK AutomatedProductionLine
VAR
    SequenceStep : INT := 0;
END_VAR

MotorForward := FALSE;
MotorReverse := FALSE;
CompletionLight := FALSE;

IF NOT Mode THEN
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
    CompletionLight := FALSE;
ELSE
    MotorReverse := FALSE;

    CASE SequenceStep OF
        0:
            IF SensorA AND ButtonA THEN
                SequenceStep := 1;
            END_IF;

        1:
            MotorForward := TRUE;
            IF SensorB THEN
                MotorForward := FALSE;
                SequenceStep := 2;
            END_IF;

        2:
            IF ButtonB THEN
                SequenceStep := 3;
            END_IF;

        3:
            MotorForward := TRUE;
            IF SensorC THEN
                MotorForward := FALSE;
                SequenceStep := 4;
            END_IF;

        4:
            IF ButtonC THEN
                SequenceStep := 5;
            END_IF;

        5:
            CompletionLight := SensorC;
            IF NOT SensorC THEN
                CompletionLight := FALSE;
                SequenceStep := 0;
            END_IF;
    END_CASE;
END_IF;

END_FUNCTION_BLOCK