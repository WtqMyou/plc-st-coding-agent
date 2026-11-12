TYPE ProdState : (WAIT_A, STAGE_A, MOVING_AB, STAGE_B, MOVING_BC, STAGE_C, COMPLETE);
END_TYPE;

FUNCTION_BLOCK ProductionLineControl
VAR
    State : ProdState := WAIT_A;
    NextState : ProdState;
END_VAR
VAR_OUTPUT
    MotorForward    : BOOL;
    MotorReverse    : BOOL;
    CompletionLight : BOOL;
END_VAR

NextState := State;

IF Mode = FALSE THEN
    MotorForward  := ForwardButton AND NOT ReverseButton;
    MotorReverse  := ReverseButton AND NOT ForwardButton;
    NextState     := WAIT_A;
ELSE
    MotorForward  := FALSE;
    MotorReverse  := FALSE;
    CASE State OF
        WAIT_A:
            IF SensorA THEN
                NextState := STAGE_A;
            END_IF;
        STAGE_A:
            IF SensorA AND ButtonA THEN
                NextState := MOVING_AB;
            END_IF;
        MOVING_AB:
            MotorForward := TRUE;
            IF SensorB THEN
                NextState := STAGE_B;
            END_IF;
        STAGE_B:
            IF SensorB AND ButtonB THEN
                NextState := MOVING_BC;
            END_IF;
        MOVING_BC:
            MotorForward := TRUE;
            IF SensorC THEN
                NextState := STAGE_C;
            END_IF;
        STAGE_C:
            IF SensorC AND ButtonC THEN
                NextState := COMPLETE;
            END_IF;
        COMPLETE:
            IF NOT SensorC THEN
                NextState := WAIT_A;
            END_IF;
    END_CASE;
END_IF;

State := NextState;

CompletionLight := (State = COMPLETE) AND SensorC;

END_FUNCTION_BLOCK