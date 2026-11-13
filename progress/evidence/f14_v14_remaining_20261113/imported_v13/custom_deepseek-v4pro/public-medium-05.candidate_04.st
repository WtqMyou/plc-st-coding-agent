(* ENGINEERING_CONTRACT
  - MotorForward/Reverse (PUB001/PUB002): manual controls selected by Mode=0; both directions inhibited on conflict.
  - MotorForward auto (PUB003/PUB004): latched start at SensorA+ButtonA or SensorB+ButtonB; reset by SensorB/SensorC; stop priority over start.
  - MotorReverse auto: forced FALSE.
  - CompletionLight (PUB004): set while Mode=1 and SensorC+ButtonC; held while SensorC=1; reset when SensorC=0.
  - Buttons are level-sensitive; no edge memory.
  - Movement latches are cleared in manual mode; completion latch survives mode switches while SensorC=1.
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
END_VAR

// Update automatic-mode latches with stop priority.
// Movement to B starts only in automatic mode and when SensorA and ButtonA are true.
// It is cleared as soon as SensorB detects the product.
tmp_MoveToB := (tmp_MoveToB OR (Mode AND SensorA AND ButtonA)) AND NOT SensorB;

// Movement to C starts similarly from B and is cleared by SensorC.
tmp_MoveToC := (tmp_MoveToC OR (Mode AND SensorB AND ButtonB)) AND NOT SensorC;

// Completion light is set only in automatic mode when product is at C and ButtonC is pressed.
// It remains on while SensorC is true and is cleared when SensorC goes false.
tmp_Completed := (tmp_Completed OR (Mode AND SensorC AND ButtonC)) AND SensorC;

IF Mode THEN
    // Automatic mode: motor forward comes from the latched movement flags.
    MotorForward := tmp_MoveToB OR tmp_MoveToC;
    MotorReverse := FALSE;
ELSE
    // Manual mode: movement automatic sequence state is cleared,
    // but the completion latch is retained so CompletionLight can
    // remain on until SensorC releases the product.
    tmp_MoveToB := FALSE;
    tmp_MoveToC := FALSE;

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