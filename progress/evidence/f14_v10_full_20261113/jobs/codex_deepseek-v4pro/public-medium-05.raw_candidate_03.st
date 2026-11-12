FUNCTION_BLOCK ProductionLineControl
(*
ENGINEERING_CONTRACT
MotorForward (PUB006/PUB007): manual ForwardButton iff not ReverseButton; auto hold while AutoStep=1 or AutoStep=3; deactivate at destination sensor B/C or on manual release/non-auto; simultaneous Forward/Reverse gives no motion.
MotorReverse (PUB004): manual ReverseButton iff not ForwardButton.
CompletionLight (PUB008): auto activate when C is reached and SensorC and ButtonC are TRUE, including same-scan arrival; retain while SensorC TRUE; reset only when SensorC FALSE.
AutoStep retains sequence state across scans; BOOL buttons are level-gated, no unstated edges.
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
                IF ButtonB THEN
                    AutoStep := 3;
                    MotorForward := TRUE;
                ELSE
                    AutoStep := 2;
                END_IF;
            ELSE
                MotorForward := TRUE;
            END_IF;

        2:
            IF ButtonB THEN
                AutoStep := 3;
                MotorForward := TRUE;
            END_IF;

        3:
            IF SensorC THEN
                AutoStep := 4;
                IF ButtonC THEN
                    CompletionLight := TRUE;
                END_IF;
            ELSE
                MotorForward := TRUE;
            END_IF;

        4:
            IF SensorC AND (CompletionLight OR ButtonC) THEN
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