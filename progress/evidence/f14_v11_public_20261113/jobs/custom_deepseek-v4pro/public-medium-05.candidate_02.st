(* ENGINEERING_CONTRACT
- Manual mode (Mode=FALSE): MotorForward set while ForwardButton AND NOT ReverseButton; MotorReverse set while ReverseButton AND NOT ForwardButton; simultaneous buttons deactivate both (PUB002).
- Automatic mode (Mode=TRUE): move_AB latch set by ButtonA R_TRIG while SensorA true; cleared when SensorB true. move_BC latch set by ButtonB while SensorB true; cleared when SensorC true.
- MotorForward = Mode AND (move_AB OR move_BC). MotorReverse is always FALSE in automatic mode (PUB003/PUB004).
- CompletionLight latch set by ButtonC R_TRIG while Mode=TRUE and SensorC true; held high; cleared when SensorC=FALSE regardless of Mode (PUB004).
- Same-scan priority: destination sensor clear wins over move set; simultaneous ForwardButton and ReverseButton -> both motor outputs FALSE.
*)

(* CONTRACT_RULES [] *)

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
    move_AB : BOOL := FALSE;
    move_BC : BOOL := FALSE;
    completion_latch : BOOL := FALSE;
    btnA_rt : R_TRIG;
    btnB_rt : R_TRIG;
    btnC_rt : R_TRIG;
END_VAR

btnA_rt(CLK := ButtonA);
btnB_rt(CLK := ButtonB);
btnC_rt(CLK := ButtonC);

IF Mode THEN
    IF btnA_rt.Q AND SensorA THEN
        move_AB := TRUE;
    END_IF;

    IF ButtonB AND SensorB THEN
        move_BC := TRUE;
    END_IF;

    IF btnC_rt.Q AND SensorC THEN
        completion_latch := TRUE;
    END_IF;
END_IF;

IF SensorB THEN
    move_AB := FALSE;
END_IF;

IF SensorC THEN
    move_BC := FALSE;
END_IF;

IF NOT SensorC THEN
    completion_latch := FALSE;
END_IF;

IF Mode THEN
    MotorForward := move_AB OR move_BC;
    MotorReverse := FALSE;
ELSE
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
END_IF;

CompletionLight := completion_latch;

END_FUNCTION_BLOCK