(* ENGINEERING_CONTRACT
 * =============================================================================
 * Production Control - 5-Station Automated Line
 * =============================================================================
 * MODES:
 * - Manual (Mode=0): ForwardButton→MotorForward, ReverseButton→MotorReverse
 *   Interlock: MotorForward AND MotorReverse never simultaneous
 *   Activation: Button held; No retention; No explicit reset defined
 *
 * - Automatic (Mode=1): State-machine progression with sensor triggers
 *   States: LOAD→WASH→WEIGH→FIRE→OUTPUT (sequential forward flow)
 *
 * AUTOMATIC STATE TRANSITIONS:
 * - ST_LOAD: SensorFeed → MotorForward (retract, moves to next station)
 *   Reset: Automatic off, manual mode
 *
 * - ST_WASH: SensorWash → MotorStop
 *   Activation: washComplete → MotorForward
 *   Reset: Automatic off, manual mode
 *
 * - ST_WEIGH: SensorWeight → MotorStop
 *   Activation: weightComplete AND qualified(100≤weight≤200) → calc firingTemp, MotorForward
 *   Activation: weightComplete AND NOT qualified → kick latch ON
 *   Reset: Automatic off, manual mode; kick requires external reset (unspecified)
 *
 * - ST_FIRE: SensorFiring → MotorStop
 *   Activation: firingComplete → MotorForward
 *   Reset: Automatic off, manual mode
 *
 * - ST_OUTPUT: SensorOutput → MotorStop, CompletionLight:=SensorOutput
 *   Retention: CompletionLight held ON while SensorOutput=TRUE; OFF when FALSE
 *   Reset: Automatic off, manual mode (light follows sensor)
 *
 * FIRING TEMP CALCULATION:
 * - Linear: weight 100→200 maps to temp 500→550
 * - Formula: firingTemp = 500.0 + (weight - 100.0) * 0.5
 * - Same-scan calculation when SensorWeight AND weightComplete both TRUE
 * - Retained until next qualified product (unspecified reset)
 *
 * UNITS/BOUNDARIES:
 * - Weight: REAL, qualified range [100.0, 200.0] inclusive
 * - Temp: REAL, output range [500.0, 550.0] inclusive
 * - All sensors: BOOL, level-triggered detection (sensor TRUE = product present)
 * =============================================================================
 *)

(* CONTRACT_RULES [] *)

TYPE StationState :
(
    ST_LOAD   := 0,
    ST_WASH   := 1,
    ST_WEIGH  := 2,
    ST_FIRE   := 3,
    ST_OUTPUT := 4
);
END_TYPE;

FUNCTION_BLOCK ProductionControl
VAR_INPUT
    Mode            : BOOL;  (* 0=manual, 1=automatic *)
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
    state              : StationState;
    prevWashComplete   : BOOL;
    prevFiringComplete : BOOL;
END_VAR

(* Initialize outputs to safe state *)
MotorForward    := FALSE;
MotorReverse    := FALSE;
kick            := kick;        (* Preserve retained state *)
CompletionLight := FALSE;
firingTemp      := firingTemp;  (* Preserve retained state *)

IF Mode = FALSE THEN
    (* ======================================================================= *)
    (* MANUAL MODE                                                             *)
    (* PUB001, PUB002, PUB003                                                  *)
    (* ======================================================================= *)
    (* Interlock: forward and reverse cannot be simultaneous *)
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

    (* Reset state machine when entering manual mode *)
    state := ST_LOAD;

ELSIF Mode = TRUE THEN
    (* ======================================================================= *)
    (* AUTOMATIC MODE                                                          *)
    (* PUB004, PUB005, PUB006, PUB007, PUB008, PUB009, PUB010, PUB011, PUB012   *)
    (* ======================================================================= *)
    MotorReverse := FALSE;  (* Only forward in automatic mode *)

    (* Edge detection for washComplete - rising edge triggers forward *)
    IF washComplete AND NOT prevWashComplete THEN
        MotorForward := TRUE;
    END_IF;
    prevWashComplete := washComplete;

    (* Edge detection for firingComplete - rising edge triggers forward *)
    IF firingComplete AND NOT prevFiringComplete THEN
        MotorForward := TRUE;
    END_IF;
    prevFiringComplete := firingComplete;

    (* State machine based on current station detection *)
    IF SensorOutput THEN
        (* ================================================================= *)
        (* STATION 5: OUTPUT (Finished Product)                              *)
        (* PUB012                                                              *)
        (* Motor stops, CompletionLight follows sensor                       *)
        (* ================================================================= *)
        state := ST_OUTPUT;
        MotorForward := FALSE;
        CompletionLight := SensorOutput;  (* ON when product present *)

    ELSIF SensorFiring THEN
        (* ================================================================= *)
        (* STATION 4: FIRING                                                 *)
        (* PUB010, PUB011                                                     *)
        (* Motor stops; wait for firingComplete → forward                    *)
        (* ================================================================= *)
        state := ST_FIRE;
        MotorForward := FALSE;
        CompletionLight := FALSE;
        (* MotorForward set on rising edge of firingComplete above *)

    ELSIF SensorWeight THEN
        (* ================================================================= *)
        (* STATION 3: WEIGHING                                                *)
        (* PUB006, PUB007, PUB008, PUB009                                     *)
        (* Motor stops; weightComplete triggers qualification check           *)
        (* ================================================================= *)
        state := ST_WEIGH;
        MotorForward := FALSE;
        CompletionLight := FALSE;

        (* Immediate calculation when weightComplete signal is received *)
        (* No edge delay - weightComplete is a one-shot from external process *)
        IF weightComplete THEN
            (* Qualification check: 100 <= weight <= 200 *)
            IF weight >= 100.0 AND weight <= 200.0 THEN
                (* Qualified: calculate firing temperature *)
                (* Linear interpolation: weight[100,200] -> temp[500,550] *)
                firingTemp := 500.0 + (weight - 100.0) * 0.5;
                kick := FALSE;
                MotorForward := TRUE;
            ELSE
                (* Unqualified: reject *)
                kick := TRUE;
                MotorForward := FALSE;
            END_IF;
        END_IF;

    ELSIF SensorWash THEN
        (* ================================================================= *)
        (* STATION 2: CLEANING                                                *)
        (* PUB004, PUB005                                                     *)
        (* Motor stops; washComplete triggers forward                        *)
        (* ================================================================= *)
        state := ST_WASH;
        MotorForward := FALSE;
        CompletionLight := FALSE;
        kick := FALSE;  (* Reset kick on new product entering wash *)

    ELSIF SensorFeed THEN
        (* ================================================================= *)
        (* STATION 1: MATERIAL LOADING                                        *)
        (* PUB004                                                              *)
        (* SensorFeed detected → start motor forward                         *)
        (* ================================================================= *)
        state := ST_LOAD;
        MotorForward := TRUE;
        CompletionLight := FALSE;
        kick := FALSE;  (* Reset kick on new product *)

    ELSE
        (* No sensor active - product in transit or line empty *)
        (* Maintain current MotorForward state from completion signals *)
        (* MotorForward already set by rising edges above *)
        CompletionLight := FALSE;
    END_IF;

END_IF;

END_FUNCTION_BLOCK