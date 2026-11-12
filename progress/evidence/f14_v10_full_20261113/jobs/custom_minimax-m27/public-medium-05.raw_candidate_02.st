(* ENGINEERING_CONTRACT *)
(*
  PubRefs: PUB001, PUB003, PUB004, PUB006, PUB007
  Mode: 0=manual, 1=automatic
  Manual (Mode=FALSE): ForwardButton→MotorForward, ReverseButton→MotorReverse; interlocked (PUB001)
  Auto (Mode=TRUE):
    IDLE+SensorA→WAIT_AT_A (PUB003)
    WAIT_AT_A+ButtonA→MOVING_AB; MotorForward=TRUE (PUB003)
    MOVING_AB+SensorB→WAIT_AT_B; MotorForward=FALSE (PUB004)
    WAIT_AT_B+ButtonB→MOVING_BC; MotorForward=TRUE (PUB004)
    MOVING_BC+SensorC→WAIT_AT_C; MotorForward=FALSE (PUB004)
    WAIT_AT_C+ButtonC→COMPLETE; CompletionLight=TRUE (PUB006)
    COMPLETE+NOT SensorC→IDLE; CompletionLight=FALSE (PUB007)
  Retention: CompletionLight holds until SensorC clears (PUB007)
  Reset on mode switch: Auto state→IDLE, motor OFF
*)
(* CONTRACT_RULES [] *)

TYPE ProdState :
(
    IDLE      := 0,
    WAIT_AT_A := 1,
    MOVING_AB := 2,
    WAIT_AT_B := 3,
    MOVING_BC := 4,
    WAIT_AT_C := 5,
    COMPLETE  := 6
);
END_TYPE;

FUNCTION_BLOCK ProdLineControl
VAR_INPUT
    Mode          : BOOL;
    ForwardButton : BOOL;
    ReverseButton : BOOL;
    SensorA       : BOOL;
    SensorB       : BOOL;
    SensorC       : BOOL;
    ButtonA       : BOOL;
    ButtonB       : BOOL;
    ButtonC       : BOOL;
END_VAR
VAR
    tmp_State : ProdState := IDLE;
END_VAR
VAR_OUTPUT
    MotorForward    : BOOL := FALSE;
    MotorReverse    : BOOL := FALSE;
    CompletionLight : BOOL := FALSE;
END_VAR

// --- Automatic Mode State Machine ---
IF Mode THEN
    CASE tmp_State OF
        IDLE :
            MotorForward    := FALSE;
            MotorReverse    := FALSE;
            CompletionLight := FALSE;
            IF SensorA THEN
                tmp_State := WAIT_AT_A;
            END_IF;

        WAIT_AT_A :
            MotorForward    := FALSE;
            MotorReverse    := FALSE;
            CompletionLight := FALSE;
            IF ButtonA THEN
                tmp_State := MOVING_AB;
            END_IF;

        MOVING_AB :
            MotorForward    := TRUE;
            MotorReverse    := FALSE;
            CompletionLight := FALSE;
            IF SensorB THEN
                tmp_State     := WAIT_AT_B;
                MotorForward  := FALSE;
            END_IF;

        WAIT_AT_B :
            MotorForward    := FALSE;
            MotorReverse    := FALSE;
            CompletionLight := FALSE;
            IF ButtonB THEN
                tmp_State := MOVING_BC;
            END_IF;

        MOVING_BC :
            MotorForward    := TRUE;
            MotorReverse    := FALSE;
            CompletionLight := FALSE;
            IF SensorC THEN
                tmp_State     := WAIT_AT_C;
                MotorForward  := FALSE;
            END_IF;

        WAIT_AT_C :
            MotorForward    := FALSE;
            MotorReverse    := FALSE;
            IF ButtonC THEN
                tmp_State       := COMPLETE;
                CompletionLight := TRUE;
            END_IF;

        COMPLETE :
            MotorForward    := FALSE;
            MotorReverse    := FALSE;
            CompletionLight := TRUE;
            IF NOT SensorC THEN
                tmp_State       := IDLE;
                CompletionLight := FALSE;
            END_IF;
    END_CASE;

// --- Manual Mode ---
ELSE
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
    tmp_State    := IDLE;
END_IF;

END_FUNCTION_BLOCK