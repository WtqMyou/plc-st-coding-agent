FUNCTION_BLOCK ProductionLineControl
VAR
    trigA : R_TRIG;
    trigB : R_TRIG;
    trigC : R_TRIG;
    movingToB : BOOL := FALSE;
    movingToC : BOOL := FALSE;
    completionLatched : BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT
MotorForward: manual = ForwardButton AND NOT ReverseButton;
  auto = movingToB OR movingToC. Hold until target sensor or mode change.
MotorReverse: manual = ReverseButton AND NOT ForwardButton;
  interlocked, both buttons => neither. No auto reverse.
CompletionLight: auto only, set on ButtonC rising edge while SensorC true,
  reset when SensorC false or mode manual. Unspecified manual completion light = off.
State movingToB/movingToC: start on source button rising edge at source sensor,
  stop on target sensor. Cleared in manual.
State completionLatched: holds until SensorC false or mode manual.
PUB001-PUB008 satisfied.
*)
(* CONTRACT_RULES [] *)

trigA(CLK := ButtonA);
trigB(CLK := ButtonB);
trigC(CLK := ButtonC);

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
        IF SensorA AND trigA.Q THEN
            movingToB := TRUE;
        ELSIF SensorB AND trigB.Q THEN
            movingToC := TRUE;
        ELSIF SensorC AND trigC.Q THEN
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