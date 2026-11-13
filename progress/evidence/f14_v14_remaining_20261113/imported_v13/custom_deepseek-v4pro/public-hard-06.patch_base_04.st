FUNCTION_BLOCK ProductionControl
VAR_INPUT
    Mode : BOOL;
    ForwardButton : BOOL;
    ReverseButton : BOOL;
    SensorFeed : BOOL;
    SensorWash : BOOL;
    SensorWeight : BOOL;
    SensorFiring : BOOL;
    SensorOutput : BOOL;
    washComplete : BOOL;
    weightComplete : BOOL;
    weight : REAL;
    firingComplete : BOOL;
END_VAR
VAR_OUTPUT
    MotorForward : BOOL;
    MotorReverse : BOOL;
    kick : BOOL;
    CompletionLight : BOOL;
    firingTemp : REAL;
END_VAR
VAR
    AutoStep : INT := 0;
    AutoInit : BOOL := FALSE;
    lastFiringTemp : REAL := 0.0;
    rtWash : R_TRIG;
    rtWeight : R_TRIG;
    rtFiring : R_TRIG;
    washEdge : BOOL;
    weightEdge : BOOL;
    firingEdge : BOOL;
    rtMode : R_TRIG;
    ModeRise : BOOL;
    tmp_unqualified : BOOL;
END_VAR

(*
ENGINEERING_CONTRACT
MotorForward: auto active in states 10/30/50/70; manual = ForwardButton AND NOT ReverseButton.
MotorReverse: manual only, interlocked with ForwardButton; both false if both buttons true.
kick: pulse on rising weightComplete when weight < 100 or weight > 200 (unqualified).
CompletionLight: combinational = SensorOutput while Mode=TRUE; off in manual.
firingTemp: stored on qualified weightComplete; formula 500 + (weight-100)*0.5, retained otherwise.
Units: weight REAL in same unit as thresholds; firingTemp REAL degrees; boundaries inclusive 100..200.
*)
(* CONTRACT_RULES [] *)

rtMode(CLK := Mode);
ModeRise := rtMode.Q;
rtWash(CLK := washComplete);
rtWeight(CLK := weightComplete);
rtFiring(CLK := firingComplete);
washEdge := rtWash.Q;
weightEdge := rtWeight.Q;
firingEdge := rtFiring.Q;

IF (NOT AutoInit) OR ModeRise THEN
    AutoInit := TRUE;
    IF SensorOutput THEN
        AutoStep := 80;
    ELSIF SensorFiring THEN
        AutoStep := 60;
    ELSIF SensorWeight THEN
        AutoStep := 40;
    ELSIF SensorWash THEN
        AutoStep := 20;
    ELSIF SensorFeed THEN
        AutoStep := 10;
    ELSE
        AutoStep := 0;
    END_IF;
END_IF;

IF NOT Mode THEN
    MotorForward := ForwardButton AND (NOT ReverseButton);
    MotorReverse := ReverseButton AND (NOT ForwardButton);
    kick := FALSE;
    CompletionLight := FALSE;
    firingTemp := lastFiringTemp;
    RETURN;
END_IF;

MotorForward := FALSE;
MotorReverse := FALSE;
kick := FALSE;
CompletionLight := FALSE;

CASE AutoStep OF
    0:
        IF SensorFeed THEN
            AutoStep := 10;
        END_IF;

    10:
        IF SensorWash THEN
            AutoStep := 20;
        END_IF;

    20:
        IF washEdge THEN
            AutoStep := 30;
        END_IF;

    30:
        IF SensorWeight THEN
            AutoStep := 40;
        END_IF;

    40:
        IF weightEdge THEN
            tmp_unqualified := (weight < 100.0) OR (weight > 200.0);
            IF tmp_unqualified THEN
                kick := TRUE;
                AutoStep := 0;
            ELSE
                lastFiringTemp := 500.0 + (weight - 100.0) * 0.5;
                AutoStep := 50;
            END_IF;
        END_IF;

    50:
        IF SensorFiring THEN
            AutoStep := 60;
        END_IF;

    60:
        IF firingEdge THEN
            AutoStep := 70;
        END_IF;

    70:
        IF SensorOutput THEN
            AutoStep := 80;
        END_IF;

    80:
        IF NOT SensorOutput THEN
            AutoStep := 0;
        END_IF;
END_CASE;

MotorForward := (AutoStep = 10) OR (AutoStep = 30) OR (AutoStep = 50) OR (AutoStep = 70);
MotorReverse := FALSE;
CompletionLight := SensorOutput;
firingTemp := lastFiringTemp;
END_FUNCTION_BLOCK