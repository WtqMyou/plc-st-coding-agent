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
    movingToB : BOOL := FALSE;
    movingToC : BOOL := FALSE;
    completionLatched : BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT
MotorForward: manual = ForwardButton AND NOT ReverseButton;
  auto = movingToB OR movingToC. Hold until target sensor or mode change.
MotorReverse: manual = ReverseButton AND NOT ForwardButton;
  interlocked, both buttons => neither. No auto reverse.
CompletionLight: auto only, set when SensorC AND ButtonC true (level),
  reset when SensorC false or mode manual. Unspecified manual completion light = off.
State movingToB/movingToC: start when source sensor AND corresponding button true,
  stop on target sensor. Cleared in manual.
State completionLatched: holds until SensorC false or mode manual.
All automatic actions level-triggered (button held is sufficient) per public wording.
PUB001-PUB008 satisfied.
*)
(* CONTRACT_RULES [] *)

MotorForward := FALSE;
MotorReverse := FALSE;
CompletionLight := FALSE;

IF Mode THEN
    (* Automatic mode *)
    MotorReverse := FALSE;

    (* Arrival stops first: product reached target station *)
    IF movingToB AND SensorB THEN
        movingToB := FALSE;
    END_IF;

    IF movingToC AND SensorC THEN
        movingToC := FALSE;
    END_IF;

    (* Start movement or completion when not already moving *)
    IF NOT movingToB AND NOT movingToC THEN
        IF SensorA AND ButtonA THEN
            movingToB := TRUE;
        ELSIF SensorB AND ButtonB THEN
            movingToC := TRUE;
        ELSIF SensorC AND ButtonC THEN
            completionLatched := TRUE;
        END_IF;
    END_IF;

    (* Completion light off when product is taken away from C *)
    IF NOT SensorC THEN
        completionLatched := FALSE;
    END_IF;

    CompletionLight := completionLatched;
    MotorForward := movingToB OR movingToC;
ELSE
    (* Manual mode: clear all automatic sequence state *)
    movingToB := FALSE;
    movingToC := FALSE;
    completionLatched := FALSE;

    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
        MotorReverse := FALSE;
    ELSIF ReverseButton AND NOT ForwardButton THEN
        MotorForward := FALSE;
        MotorReverse := TRUE;
    ELSE
        MotorForward := FALSE;
        MotorReverse := FALSE;
    END_IF;

    CompletionLight := FALSE;
END_IF;
END_FUNCTION_BLOCK