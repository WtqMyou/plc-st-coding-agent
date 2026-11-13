TYPE LineTarget : (TargetNone, TargetB, TargetC);
END_TYPE

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
    local_target : LineTarget := TargetNone;
    completionLatched : BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT
MotorForward auto: activated by ButtonA at SensorA or ButtonB at SensorB; held until target SensorB/C.
MotorForward manual: follows ForwardButton while ReverseButton is FALSE; both conflict outputs inhibited.
MotorReverse manual: follows ReverseButton while ForwardButton is FALSE; auto mode holds MotorReverse OFF.
CompletionLight: latched TRUE on Mode & SensorC & ButtonC; retained until SensorC becomes FALSE.
Same-scan priority: SensorC, then SensorB, then SensorA; arrival plus next button uses final current inputs.
Mode-transition retention is unspecified; auto target and completion state are retained when mode changes.
Units/boundaries: BOOL logic only; no time or arithmetic boundaries.
*)

(* CONTRACT_RULES [] *)

IF Mode THEN
    CASE local_target OF
        TargetNone:
            IF SensorC THEN
                IF ButtonC THEN
                    completionLatched := TRUE;
                END_IF;
            ELSIF SensorB THEN
                IF ButtonB THEN
                    local_target := TargetC;
                END_IF;
            ELSIF SensorA AND ButtonA THEN
                local_target := TargetB;
            END_IF;

        TargetB:
            IF SensorC THEN
                local_target := TargetNone;
                IF ButtonC THEN
                    completionLatched := TRUE;
                END_IF;
            ELSIF SensorB THEN
                local_target := TargetNone;
                IF ButtonB THEN
                    local_target := TargetC;
                END_IF;
            END_IF;

        TargetC:
            IF SensorC THEN
                local_target := TargetNone;
                IF ButtonC THEN
                    completionLatched := TRUE;
                END_IF;
            END_IF;
    END_CASE;

    IF local_target <> TargetNone THEN
        MotorForward := TRUE;
    ELSE
        MotorForward := FALSE;
    END_IF;
    MotorReverse := FALSE;
ELSE
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
END_IF;

IF NOT SensorC THEN
    completionLatched := FALSE;
END_IF;

CompletionLight := completionLatched;

END_FUNCTION_BLOCK