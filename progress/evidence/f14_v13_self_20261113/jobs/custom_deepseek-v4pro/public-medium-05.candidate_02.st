(* ENGINEERING_CONTRACT
  - MotorForward/Reverse (PUB001/PUB002): manual controls selected by Mode=0; both directions inhibited on conflict.
  - MotorForward auto (PUB003/PUB004): latched start at SensorA+ButtonA or SensorB+ButtonB; reset by SensorB/SensorC; stop priority over start.
  - MotorReverse auto: forced FALSE.
  - CompletionLight (PUB004): set while Mode=1 and SensorC+ButtonC; held while SensorC=1; reset when SensorC=0.
  - Automatic buttons are edge-triggered; manual direction buttons remain level.
  - Retained latches survive mode switches; arrival resets occur even in manual.
  - BOOL arithmetic; no numeric units.
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB_ProductionLine
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
    tmp_MoveToB : BOOL := FALSE;
    tmp_MoveToC : BOOL := FALSE;
    tmp_Completed : BOOL := FALSE;
    tmp_TrigA : R_TRIG;
    tmp_TrigB : R_TRIG;
    tmp_TrigC : R_TRIG;
END_VAR

tmp_TrigA(CLK := ButtonA);
tmp_TrigB(CLK := ButtonB);
tmp_TrigC(CLK := ButtonC);

// Update automatic-mode latches with stop priority.
// Automatic commands require a rising edge on the matching button while the product sensor is true.
// Movement to B starts on a ButtonA edge with SensorA true and clears when SensorB detects the product.
tmp_MoveToB := (tmp_MoveToB OR (Mode AND SensorA AND tmp_TrigA.Q)) AND NOT SensorB;

// Movement to C starts on a ButtonB edge with SensorB true and clears when SensorC detects the product.
tmp_MoveToC := (tmp_MoveToC OR (Mode AND SensorB AND tmp_TrigB.Q)) AND NOT SensorC;

// Completion light is set on a ButtonC edge with SensorC true and remains on while SensorC is true.
// It clears as soon as the product is removed from SensorC.
tmp_Completed := (tmp_Completed OR (Mode AND SensorC AND tmp_TrigC.Q)) AND SensorC;

IF Mode THEN
    // Automatic mode: motor forward comes from the latched movement flags.
    MotorForward := tmp_MoveToB OR tmp_MoveToC;
    MotorReverse := FALSE;
ELSE
    // Manual mode: direct pushbutton control with interlock.
    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
        MotorReverse := FALSE;
    ELSIF ReverseButton AND NOT ForwardButton THEN
        MotorForward := FALSE;
        MotorReverse := TRUE;
    ELSE
        // Both or neither pressed: inhibit both directions.
        MotorForward := FALSE;
        MotorReverse := FALSE;
    END_IF;
END_IF;

// Completion light always reflects the automatic completion latch.
CompletionLight := tmp_Completed;

END_FUNCTION_BLOCK