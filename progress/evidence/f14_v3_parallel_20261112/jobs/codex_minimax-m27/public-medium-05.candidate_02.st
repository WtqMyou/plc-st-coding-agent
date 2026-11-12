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
    MotorForward : BOOL := FALSE;
    MotorReverse : BOOL := FALSE;
    CompletionLight : BOOL := FALSE;
END_VAR

VAR
    State : INT := 0;
    PrevButtonA : BOOL := FALSE;
    PrevButtonB : BOOL := FALSE;
    PrevButtonC : BOOL := FALSE;
END_VAR

IF Mode = FALSE THEN
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
ELSE
    MotorForward := FALSE;
    MotorReverse := FALSE;
    
    CASE State OF
        0:
            IF SensorA THEN
                State := 1;
            END_IF;
            
        1:
            IF ButtonA AND NOT PrevButtonA THEN
                MotorForward := TRUE;
                State := 2;
            END_IF;
            
        2:
            IF SensorB THEN
                MotorForward := FALSE;
                State := 3;
            END_IF;
            
        3:
            IF ButtonB AND NOT PrevButtonB THEN
                MotorForward := TRUE;
                State := 4;
            END_IF;
            
        4:
            IF SensorC THEN
                MotorForward := FALSE;
                State := 5;
            END_IF;
            
        5:
            IF ButtonC AND NOT PrevButtonC THEN
                CompletionLight := TRUE;
                State := 6;
            END_IF;
            
        6:
            IF NOT SensorC THEN
                CompletionLight := FALSE;
                State := 0;
            END_IF;
    END_CASE;
    
    PrevButtonA := ButtonA;
    PrevButtonB := ButtonB;
    PrevButtonC := ButtonC;
END_IF;

END_FUNCTION_BLOCK