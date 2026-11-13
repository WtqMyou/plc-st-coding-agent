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
    CompletionLight : BOOL;
    firingTemp      : REAL;
END_VAR
VAR
    eState          : INT := 0;
    tmp_WashTrig    : R_TRIG;
    tmp_WeightTrig  : R_TRIG;
    tmp_FiringTrig  : R_TRIG;
    tmp_FeedPrev    : BOOL := FALSE;
END_VAR

(*
ENGINEERING_CONTRACT
================================================================================
PUB001: Mode switch (0=manual, 1=automatic)
PUB002: Manual interlocks prevent simultaneous Forward/Reverse; priority=inhibit both
PUB003: Auto sequence: FEED→WASH→WEIGH→FIRING→OUTPUT→IDLE (reset on next SensorFeed)
PUB004: Weight check [100,200]; unqualified→kick=TRUE; qualified→firingTemp=(weight-100)*0.5+500
PUB006: washComplete starts MotorForward (rising-edge, state WASH)
PUB007: weightComplete triggers weight evaluation and either kick or motor start (rising-edge)
PUB008: firingComplete starts MotorForward (rising-edge, state FIRING)
PUB010: CompletionLight := SensorOutput (retention on product presence)
PUB012: Motor stops on sensor arrival; motor starts on completion signal or qualified weight
================================================================================
Output activation table:
| Output         | Set condition                              | Reset condition        |
|----------------|--------------------------------------------|------------------------|
| MotorForward   | SensorFeed in IDLE; washComplete in WASH;  | Sensor at next station;|
|                | weightComplete in WEIGH when qualified;    | Mode change;           |
|                | firingComplete in FIRING                   | IDLE;                  |
| MotorReverse   | ReverseButton AND NOT ForwardButton; Mode=0| Mode!=0; ForwardButton |
| kick           | weightComplete in WEIGH when unqualified   | Mode change; WEIGH entry|
| CompletionLight| SensorOutput=TRUE in OUTPUT                | SensorOutput=FALSE;Mode|
| firingTemp     | weightComplete in WEIGH when qualified     | Mode change; WEIGH entry|
================================================================================
*)

tmp_FeedPrev := SensorFeed;

CASE eState OF
    0: // IDLE
        MotorForward := FALSE;
        MotorReverse := FALSE;
        kick := FALSE;
        firingTemp := 0.0;
        IF Mode = FALSE THEN
            MotorForward := ForwardButton;
            MotorReverse := (NOT ForwardButton) AND ReverseButton;
        ELSE
            IF SensorFeed AND NOT tmp_FeedPrev THEN
                MotorForward := TRUE;
                eState := 1;
            END_IF;
        END_IF;

    1: // WASH
        IF Mode = FALSE THEN
            MotorForward := FALSE;
            MotorReverse := FALSE;
            kick := FALSE;
            firingTemp := 0.0;
            eState := 0;
        ELSE
            kick := FALSE;
            firingTemp := 0.0;
            tmp_WashTrig(CLK := washComplete);
            IF SensorWash THEN
                MotorForward := FALSE;
            END_IF;
            IF tmp_WashTrig.Q THEN
                MotorForward := TRUE;
                eState := 2;
            END_IF;
        END_IF;

    2: // WEIGH
        IF Mode = FALSE THEN
            MotorForward := FALSE;
            MotorReverse := FALSE;
            kick := FALSE;
            firingTemp := 0.0;
            eState := 0;
        ELSE
            IF SensorWeight THEN
                MotorForward := FALSE;
            END_IF;
            tmp_WeightTrig(CLK := weightComplete);
            IF tmp_WeightTrig.Q THEN
                IF (weight >= 100.0) AND (weight <= 200.0) THEN
                    firingTemp := (weight - 100.0) * 0.5 + 500.0;
                    kick := FALSE;
                    MotorForward := TRUE;
                    eState := 3;
                ELSE
                    kick := TRUE;
                    firingTemp := 0.0;
                    MotorForward := TRUE;
                    eState := 3;
                END_IF;
            END_IF;
        END_IF;

    3: // FIRING
        IF Mode = FALSE THEN
            MotorForward := FALSE;
            MotorReverse := FALSE;
            kick := FALSE;
            firingTemp := 0.0;
            eState := 0;
        ELSE
            IF SensorFiring THEN
                MotorForward := FALSE;
            END_IF;
            tmp_FiringTrig(CLK := firingComplete);
            IF tmp_FiringTrig.Q THEN
                MotorForward := TRUE;
                eState := 4;
            END_IF;
        END_IF;

    4: // OUTPUT
        IF Mode = FALSE THEN
            MotorForward := FALSE;
            MotorReverse := FALSE;
            kick := FALSE;
            firingTemp := 0.0;
            CompletionLight := FALSE;
            eState := 0;
        ELSE
            IF SensorOutput THEN
                MotorForward := FALSE;
                CompletionLight := TRUE;
            ELSE
                CompletionLight := FALSE;
            END_IF;
            IF NOT SensorOutput AND (NOT MotorForward) THEN
                eState := 0;
            END_IF;
        END_IF;
END_CASE;

(* CONTRACT_RULES
[
  {"kind": "hold_until_reset", "output": "kick", "set_input": "weightComplete", "reset_input": null},
  {"kind": "hold_until_reset", "output": "firingTemp", "set_input": "weightComplete", "reset_input": null}
]
*)
END_FUNCTION_BLOCK