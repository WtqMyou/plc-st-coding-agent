TYPE AutoState : (IDLE, MOVING_TO_B, WAIT_B, MOVING_TO_C, WAIT_C);
END_TYPE;

FUNCTION_BLOCK ProductionLineControl
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
    State : AutoState := IDLE;
    CompletionLatched : BOOL := FALSE;
END_VAR

MotorForward := FALSE;
MotorReverse := FALSE;
CompletionLight := FALSE;

IF NOT Mode THEN
    State := IDLE;
    CompletionLatched := FALSE;

    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
    ELSIF ReverseButton AND NOT ForwardButton THEN
        MotorReverse := TRUE;
    END_IF;
ELSE
    CASE State OF
        IDLE:
            IF SensorA AND ButtonA THEN
                State := MOVING_TO_B;
            ELSIF SensorB THEN
                State := WAIT_B;
            ELSIF SensorC THEN
                State := WAIT_C;
            END_IF;

        MOVING_TO_B:
            IF SensorB THEN
                State := WAIT_B;
            END_IF;

        WAIT_B:
            IF NOT SensorB THEN
                State := IDLE;
            ELSIF ButtonB THEN
                State := MOVING_TO_C;
            END_IF;

        MOVING_TO_C:
            IF SensorC THEN
                State := WAIT_C;
            END_IF;

        WAIT_C:
            IF SensorC AND ButtonC THEN
                CompletionLatched := TRUE;
            END_IF;

            IF NOT SensorC THEN
                State := IDLE;
                CompletionLatched := FALSE;
            END_IF;
    END_CASE;

    MotorForward := (State = MOVING_TO_B) OR (State = MOVING_TO_C);
    CompletionLight := CompletionLatched AND SensorC;
END_IF;
END_FUNCTION_BLOCK