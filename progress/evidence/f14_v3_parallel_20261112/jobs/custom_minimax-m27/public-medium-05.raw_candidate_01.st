TYPE ProdState :
(
    WAIT_A      : UINT := 0,
    STAGE_A     : UINT := 1,
    MOVING_AB   : UINT := 2,
    STAGE_B     : UINT := 3,
    MOVING_BC   : UINT := 4,
    STAGE_C     : UINT := 5,
    COMPLETE    : UINT := 6
);
END_TYPE

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
    // Manual Mode
    MotorForward  := ForwardButton AND NOT ReverseButton;
    MotorReverse  := ReverseButton AND NOT ForwardButton;
    NextState     := WAIT_A;
ELSE
    // Automatic Mode
    MotorForward  := FALSE;
    MotorReverse  := FALSE;

    IF State = WAIT_A THEN
        IF SensorA THEN
            NextState := STAGE_A;
        END_IF
    ELSIF State = STAGE_A THEN
        IF SensorA AND ButtonA THEN
            NextState := MOVING_AB;
        END_IF
    ELSIF State = MOVING_AB THEN
        MotorForward := TRUE;
        IF SensorB THEN
            NextState := STAGE_B;
        END_IF
    ELSIF State = STAGE_B THEN
        IF SensorB AND ButtonB THEN
            NextState := MOVING_BC;
        END_IF
    ELSIF State = MOVING_BC THEN
        MotorForward := TRUE;
        IF SensorC THEN
            NextState := STAGE_C;
        END_IF
    ELSIF State = STAGE_C THEN
        IF SensorC AND ButtonC THEN
            NextState := COMPLETE;
        END_IF
    ELSIF State = COMPLETE THEN
        IF NOT SensorC THEN
            NextState := WAIT_A;
        END_IF
    END_IF;
END_IF;

State := NextState;

CompletionLight := (State = COMPLETE) AND SensorC;

END_FUNCTION_BLOCK