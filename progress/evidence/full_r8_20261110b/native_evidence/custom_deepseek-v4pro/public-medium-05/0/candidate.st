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
    state : INT := 0;
    completedC : BOOL := FALSE;
    prev_Mode : BOOL := FALSE;
    prev_CompletionLight : BOOL := FALSE;
    prev_AutoFwd : BOOL := FALSE;
END_VAR

IF NOT Mode THEN
    (* Manual mode *)
    state := 0;
    completedC := FALSE;
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
    CompletionLight := FALSE;
ELSE
    (* Automatic mode *)
    MotorReverse := FALSE;

    (* Clear completion flag when product is removed from C *)
    IF NOT SensorC THEN
        completedC := FALSE;
    END_IF;

    CASE state OF
        0: (* IDLE *)
            MotorForward := FALSE;
            IF SensorA AND ButtonA THEN
                state := 1;
                MotorForward := TRUE;
            ELSIF SensorB AND ButtonB THEN
                state := 2;
                MotorForward := TRUE;
            ELSIF SensorC AND ButtonC THEN
                completedC := TRUE;
            END_IF;

        1: (* MOVING A -> B *)
            IF SensorB THEN
                state := 0;
                MotorForward := FALSE;
            ELSE
                MotorForward := TRUE;
            END_IF;

        2: (* MOVING B -> C *)
            IF SensorC THEN
                state := 0;
                MotorForward := FALSE;
            ELSE
                MotorForward := TRUE;
            END_IF;
    END_CASE;

    CompletionLight := completedC AND SensorC;
END_IF;

(* Update history *)
prev_Mode := Mode;
prev_CompletionLight := CompletionLight;
prev_AutoFwd := Mode AND MotorForward;

END_FUNCTION_BLOCK