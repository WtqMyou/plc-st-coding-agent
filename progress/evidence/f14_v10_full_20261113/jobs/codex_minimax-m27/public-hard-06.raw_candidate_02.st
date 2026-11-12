(* ENGINEERING_CONTRACT *)
(*
┌──────────────────┬────────────────────────────────────────────────────────────────────────┐
│ Output/State     │ Activation, Retention, Reset, Priority, Units                          │
├──────────────────┼────────────────────────────────────────────────────────────────────────┤
│ MotorForward     │ Active during FEED, TRANSPORT_TO_WEIGH, TRANSPORT_TO_FIRING states     │
│                  │ in automatic mode only. Deactivated on state exit. PUB003, PUB006      │
├──────────────────┼────────────────────────────────────────────────────────────────────────┤
│ MotorReverse     │ Active during KICK state only (automatic mode). Deactivated on exit.   │
│                  │ Interlocked with MotorForward in manual mode. PUB002                   │
├──────────────────┼────────────────────────────────────────────────────────────────────────┤
│ kick             │ Latched HIGH when weight < 100 OR weight > 200 in WEIGH state.         │
│                  │ Deactivated when material exits wash station (SensorWash=FALSE).       │
│                  │ Single rejection per material cycle. PUB010                            │
├──────────────────┼────────────────────────────────────────────────────────────────────────┤
│ CompletionLight  │ Latched HIGH when SensorOutput=TRUE in OUTPUT state.                   │
│                  │ Deactivated when SensorOutput=FALSE (product removed).                 │
│                  │ No manual override specified. PUB012                                   │
├──────────────────┼────────────────────────────────────────────────────────────────────────┤
│ firingTemp       │ Calculated once when weight passes qualification check.                │
│                  │ Value: 500 + (weight - 100) * 0.5, range [500, 550]. Retained.         │
│                  │ PUB011                                                                   │
├──────────────────┼────────────────────────────────────────────────────────────────────────┤
│ State Machine    │ States: IDLE(0), FEED(1), WASH_WAIT(2), WEIGH(3), KICK(4),             │
│                  │ TRANSPORT_TO_FIRING(5), FIRING_WAIT(6), TRANSPORT_TO_OUTPUT(7),        │
│                  │ OUTPUT(8). Same-scan priority: sensor arrival > state transition.      │
│                  │ PUB003-PUB012                                                           │
└──────────────────┴────────────────────────────────────────────────────────────────────────┘
*)

(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"CompletionLight","set_input":"SensorOutput","reset_input":"NOT SensorOutput"}] *)

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
    tmp_state : INT := 0;
    tmp_prevSensorFeed : BOOL := FALSE;
    tmp_prevSensorWash : BOOL := FALSE;
    tmp_prevSensorWeight : BOOL := FALSE;
    tmp_prevSensorFiring : BOOL := FALSE;
END_VAR

// Reset all outputs at start of scan
MotorForward := FALSE;
MotorReverse := FALSE;
kick := FALSE;
CompletionLight := FALSE;

IF Mode = FALSE THEN
    // Manual Mode (PUB001, PUB002)
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
ELSE
    // Automatic Mode (PUB003-PUB012)
    CASE tmp_state OF
        0: // IDLE - waiting for material at feed station
            IF SensorFeed THEN
                tmp_state := 1;
            END_IF;
            
        1: // FEED - transport to cleaning station
            MotorForward := TRUE;
            IF SensorWash THEN
                tmp_state := 2;
                MotorForward := FALSE;
            END_IF;
            
        2: // WASH_WAIT - waiting for cleaning completion
            IF washComplete THEN
                tmp_state := 3;
            END_IF;
            
        3: // WEIGH - process weight measurement
            IF weightComplete THEN
                IF weight < 100.0 OR weight > 200.0 THEN
                    // Unqualified: initiate kick
                    kick := TRUE;
                    MotorReverse := TRUE;
                    tmp_state := 4;
                ELSE
                    // Qualified: calculate firing temperature
                    firingTemp := 500.0 + (weight - 100.0) * 0.5;
                    MotorForward := TRUE;
                    tmp_state := 5;
                END_IF;
            END_IF;
            
        4: // KICK - reverse transport to exit wash station
            kick := TRUE;
            MotorReverse := TRUE;
            IF NOT SensorWash THEN
                kick := FALSE;
                MotorReverse := FALSE;
                tmp_state := 0;
            END_IF;
            
        5: // TRANSPORT_TO_FIRING
            MotorForward := TRUE;
            IF SensorFiring THEN
                tmp_state := 6;
                MotorForward := FALSE;
            END_IF;
            
        6: // FIRING_WAIT - waiting for firing completion
            IF firingComplete THEN
                tmp_state := 7;
            END_IF;
            
        7: // TRANSPORT_TO_OUTPUT
            MotorForward := TRUE;
            IF SensorOutput THEN
                tmp_state := 8;
                MotorForward := FALSE;
            END_IF;
            
        8: // OUTPUT - product complete, light on
            IF SensorOutput THEN
                CompletionLight := TRUE;
            ELSE
                CompletionLight := FALSE;
                tmp_state := 0;
            END_IF;
            
    END_CASE;
END_IF;

END_FUNCTION_BLOCK