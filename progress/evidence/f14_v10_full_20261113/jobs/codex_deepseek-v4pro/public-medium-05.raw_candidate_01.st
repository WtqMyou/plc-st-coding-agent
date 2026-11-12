FUNCTION_BLOCK ProductionLineControl
(*
ENGINEERING_CONTRACT
MotorForward (PUB001/PUB002/PUB003): activate manual ForwardButton or auto transfer state; hold through transfer to destination sensor; deactivate at destination sensor, manual release, or not in transfer state; simultaneous manual Forward/Reverse is interlocked, no motion.
MotorReverse (PUB002): activate only manual ReverseButton; no hold; deactivate on release or ForwardButton.
CompletionLight (PUB003): activate in auto at C while SensorC and ButtonC are TRUE; retain while SensorC remains TRUE; deactivation only when SensorC becomes FALSE; manual Mode does not reset it.
Bounds/units: BOOL inputs, BOOL outputs, discrete scan steps; buttons are level-gated, not edge-only.
Unspecified: simultaneous manual Forward/Reverse means no motion; automatic step is retained across mode changes.
*)
(* CONTRACT_RULES [] *)
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
    AutoStep : INT := 0;
END_VAR

MotorForward := FALSE;
MotorReverse := FALSE;

IF NOT SensorC THEN
    CompletionLight := FALSE;
END_IF;

IF Mode THEN
    CASE AutoStep OF
        0:
            IF SensorA AND ButtonA THEN
                AutoStep := 1;
                MotorForward := TRUE;
            END_IF;

        1:
            IF SensorB THEN
                AutoStep := 2;
            END_IF;

        2:
            IF ButtonB THEN
                AutoStep := 3;
                MotorForward := TRUE;
            END_IF;

        3:
            IF SensorC THEN
                AutoStep := 4;
            END_IF;

        4:
            IF SensorC AND ButtonC THEN
                CompletionLight := TRUE;
            END_IF;
            IF NOT SensorC THEN
                AutoStep := 0;
            END_IF;
    END_CASE;
ELSE
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
END_IF;
END_FUNCTION_BLOCK