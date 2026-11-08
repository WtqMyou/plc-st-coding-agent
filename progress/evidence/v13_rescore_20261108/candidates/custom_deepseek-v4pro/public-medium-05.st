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
    step : INT := 0;
    btnA_prev : BOOL := FALSE;
    btnB_prev : BOOL := FALSE;
    btnC_prev : BOOL := FALSE;
    mode_prev : BOOL := FALSE;
    btnA_rise : BOOL;
    btnB_rise : BOOL;
    btnC_rise : BOOL;
    mode_fall : BOOL;
    forward_req : BOOL := FALSE;
    completion_trig : BOOL := FALSE;
END_VAR

// Edge detection
btnA_rise := ButtonA AND NOT btnA_prev;
btnB_rise := ButtonB AND NOT btnB_prev;
btnC_rise := ButtonC AND NOT btnC_prev;
mode_fall := mode_prev AND NOT Mode;

// Update history
btnA_prev := ButtonA;
btnB_prev := ButtonB;
btnC_prev := ButtonC;
mode_prev := Mode;

// Clear automatic process on falling edge to manual
IF mode_fall THEN
    step := 0;
    forward_req := FALSE;
    completion_trig := FALSE;
END_IF;

IF Mode THEN
    // Automatic mode
    CASE step OF
        0:
            forward_req := FALSE;
            completion_trig := FALSE;
            IF SensorA AND btnA_rise THEN
                step := 1;
                forward_req := TRUE;
            END_IF;
        1:
            forward_req := TRUE;
            completion_trig := FALSE;
            IF SensorB THEN
                step := 2;
                forward_req := FALSE;
            END_IF;
        2:
            forward_req := FALSE;
            completion_trig := FALSE;
            IF SensorB AND btnB_rise THEN
                step := 3;
                forward_req := TRUE;
            END_IF;
        3:
            forward_req := TRUE;
            completion_trig := FALSE;
            IF SensorC THEN
                step := 4;
                forward_req := FALSE;
            END_IF;
        4:
            forward_req := FALSE;
            IF SensorC AND btnC_rise THEN
                completion_trig := TRUE;
            END_IF;
            IF NOT SensorC THEN
                completion_trig := FALSE;
                step := 0;
            END_IF;
    END_CASE;

    MotorForward := forward_req;
    MotorReverse := FALSE;
ELSE
    // Manual mode
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
END_IF;

CompletionLight := Mode AND SensorC AND completion_trig;

END_FUNCTION_BLOCK