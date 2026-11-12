(* ENGINEERING_CONTRACT
 * Production Control - 5-Station Line
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
 * - ST_LOAD: SensorFeed → MotorForward (moves to cleaning station)
 * - ST_WASH: SensorWash → MotorStop; washComplete rising edge → MotorForward
 * - ST_WEIGH: SensorWeight → MotorStop; weightComplete rising edge:
 *   • weight in [100,200] → calc firingTemp (500+0.5*(w-100)), MotorForward
 *   • weight outside range → kick:=TRUE
 * - ST_FIRE: SensorFiring → MotorStop; firingComplete rising edge → MotorForward
 * - ST_OUTPUT: SensorOutput → MotorStop, CompletionLight:=SensorOutput
 *
 * UNITS/BOUNDARIES: Weight REAL in [100,200], Temp REAL in [500,550]
 * =============================================================================
 *)

(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"kick","set_input":"weightComplete","reset_input":null}] *)

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
    kick            : BOOL;
    CompletionLight : BOOL;
    firingTemp      : REAL;
END_VAR

VAR
    state               : StationState;
    prevWashComplete    : BOOL;
    prevWeightComplete  : BOOL;
    prevFiringComplete  : BOOL;
    tmp_MotorForwardCmd : BOOL;
END_VAR

(* Rising edge detection - evaluate BEFORE any state transitions *)
VAR
    washCompleteRising   : BOOL;
    weightCompleteRising : BOOL;
    firingCompleteRising : BOOL;
END_VAR

washCompleteRising   := washComplete   AND NOT prevWashComplete;
weightCompleteRising := weightComplete AND NOT prevWeightComplete;
firingCompleteRising := firingComplete AND NOT prevFiringComplete;

(* Update previous states AFTER edge detection *)
prevWashComplete   := washComplete;
prevWeightComplete := weightComplete;
prevFiringComplete := firingComplete;

(* Default outputs - safety state *)
MotorForward    := FALSE;
MotorReverse    := FALSE;
CompletionLight := FALSE;

IF Mode = FALSE THEN
    (* ======================================================================= *)
    (* MANUAL MODE - PUB001, PUB002, PUB003                                    *)
    (* ======================================================================= *)
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

    state := ST_LOAD;

ELSE
    (* ======================================================================= *)
    (* AUTOMATIC MODE - PUB004-PUB012                                           *)
    (* ======================================================================= *)
    MotorReverse := FALSE;

    (* Completion edges set motor forward command - takes priority *)
    IF washCompleteRising THEN
        tmp_MotorForwardCmd := TRUE;
    ELSIF firingCompleteRising THEN
        tmp_MotorForwardCmd := TRUE;
    ELSE
        tmp_MotorForwardCmd := FALSE;
    END_IF;

    (* Kick latch: activated on weightComplete rising edge per contract *)
    IF weightCompleteRising THEN
        IF weight >= 100.0 AND weight <= 200.0 THEN
            kick := FALSE;
        ELSE
            kick := TRUE;
        END_IF;
    END_IF;

    (* Firing temp: calculated on weightComplete rising edge for qualified weight *)
    IF weightCompleteRising THEN
        IF weight >= 100.0 AND weight <= 200.0 THEN
            firingTemp := 500.0 + (weight - 100.0) * 0.5;
        END_IF;
    END_IF;

    (* State machine based on sensor detection *)
    IF SensorOutput THEN
        state := ST_OUTPUT;
        tmp_MotorForwardCmd := FALSE;
        CompletionLight := TRUE;

    ELSIF SensorFiring THEN
        state := ST_FIRE;
        (* Only clear if no completion edge overrode *)
        IF NOT firingCompleteRising THEN
            tmp_MotorForwardCmd := FALSE;
        END_IF;
        CompletionLight := FALSE;

    ELSIF SensorWeight THEN
        state := ST_WEIGH;
        IF NOT weightCompleteRising THEN
            tmp_MotorForwardCmd := FALSE;
        END_IF;
        CompletionLight := FALSE;

    ELSIF SensorWash THEN
        state := ST_WASH;
        IF NOT washCompleteRising THEN
            tmp_MotorForwardCmd := FALSE;
        END_IF;
        CompletionLight := FALSE;

    ELSIF SensorFeed THEN
        state := ST_LOAD;
        tmp_MotorForwardCmd := TRUE;
        CompletionLight := FALSE;
        kick := FALSE;

    ELSE
        (* No sensor active - product in transit *)
        CompletionLight := FALSE;
    END_IF;

END_IF;

(* Apply accumulated motor forward command *)
MotorForward := tmp_MotorForwardCmd;

END_FUNCTION_BLOCK