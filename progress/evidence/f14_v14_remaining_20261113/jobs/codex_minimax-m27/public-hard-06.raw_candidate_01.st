(*
ENGINEERING_CONTRACT
===================
PUB001: Mode 0=Manual, 1=Automatic (VAR_INPUT Mode)
PUB003: Manual interlock - ForwardButton→MotorForward, ReverseButton→MotorReverse, mutually exclusive
PUB002: Automatic sequential transport: Feed→Wash→Weigh→Fire→Output stations
PUB004: Station arrival detected by sensors; motor stops, awaits completion signal, then advances
PUB006: Weight qualification: qualified if 100<=weight<=200; else kick initiated
PUB007: FiringTemp calculation: weight[100,200]→temp[500,550] via linear interpolation
PUB008: CompletionLight ON when product detected at output, OFF when product removed
PUB005/P UB009-PUB012: washComplete/weightComplete/firingComplete are external process signals

OUTPUT STATE RETENTION
- MotorForward/MotorReverse: combinational per Mode selection, no retention across modes
- kick: pulse on weight qualification failure, no hold required
- CompletionLight: retained based on SensorOutput (hold until product removed)
- firingTemp: retained value written at weight station, held through firing until output

SCAN BEHAVIOR
- Sequential automatic states evaluate same-scan final state before output
- TON not required; all timing handled externally via completion signals
- Direction rule: MotorForward and MotorReverse never energized together
*)

FUNCTION_BLOCK ProductionControl
VAR_INPUT
    Mode            : BOOL;
    ForwardButton   : BOOL;
    ReverseButton   : BOOL;
    SensorFeed      : BOOL;
    SensorWash      : BOOL;
    SensorWeight    : BOOL;
    SensorFiring    : BOOL;
    SensorOutput    : BOOL;
    washComplete    : BOOL;
    weightComplete  : BOOL;
    weight          : REAL;
    firingComplete  : BOOL;
END_VAR

VAR_OUTPUT
    MotorForward    : BOOL;
    MotorReverse    : BOOL;
    kick             : BOOL;
    CompletionLight  : BOOL;
    firingTemp       : REAL;
END_VAR

VAR
    stepPosition    : INT := 0;
    localKick       : BOOL := FALSE;
END_VAR

(* CONTRACT_RULES [] *)

CASE stepPosition OF
    0: (* At feed station - waiting for material *)
        IF SensorFeed THEN
            MotorForward := TRUE;
            stepPosition := 1;
        END_IF

    1: (* Moving to wash station - detecting arrival *)
        IF SensorWash THEN
            MotorForward := FALSE;
            stepPosition := 2;
        END_IF

    2: (* At wash station - waiting for washComplete *)
        IF washComplete THEN
            MotorForward := TRUE;
            stepPosition := 3;
        END_IF

    3: (* Moving to weight station - detecting arrival *)
        IF SensorWeight THEN
            MotorForward := FALSE;
            stepPosition := 4;
        END_IF

    4: (* At weight station - waiting for weightComplete *)
        IF weightComplete THEN
            IF (weight >= 100.0) AND (weight <= 200.0) THEN
                firingTemp := 500.0 + (weight - 100.0) * (50.0 / 100.0);
                MotorForward := TRUE;
                stepPosition := 5;
            ELSE
                localKick := TRUE;
                kick := TRUE;
                MotorReverse := TRUE;
                stepPosition := 6;
            END_IF
        END_IF

    5: (* Moving to firing station - detecting arrival *)
        IF SensorFiring THEN
            MotorForward := FALSE;
            stepPosition := 7;
        END_IF

    6: (* Rejection - returning to feed station *)
        localKick := FALSE;
        kick := FALSE;
        IF NOT SensorFeed THEN
            MotorReverse := FALSE;
            stepPosition := 0;
        END_IF

    7: (* At firing station - waiting for firingComplete *)
        IF firingComplete THEN
            MotorForward := TRUE;
            stepPosition := 8;
        END_IF

    8: (* Moving to output station - detecting arrival *)
        IF SensorOutput THEN
            MotorForward := FALSE;
            stepPosition := 9;
        END_IF

    9: (* At output station - waiting for product removal *)
        CompletionLight := TRUE;

    ELSE
        stepPosition := 0;
END_CASE

IF Mode = 0 THEN
    stepPosition := 0;
    MotorForward := FALSE;
    MotorReverse := FALSE;
    kick := FALSE;
    CompletionLight := FALSE;
    localKick := FALSE;
    firingTemp := 0.0;
    
    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
    ELSIF ReverseButton AND NOT ForwardButton THEN
        MotorReverse := TRUE;
    END_IF
END_IF

IF NOT SensorOutput AND stepPosition = 9 THEN
    CompletionLight := FALSE;
    stepPosition := 0;
END_IF

END_FUNCTION_BLOCK