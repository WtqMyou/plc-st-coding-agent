(* ENGINEERING_CONTRACT *)
(*
Mode behavior (PUB001):
- Mode=0: Manual mode (ForwardButton→MotorForward, ReverseButton→MotorReverse)
- Mode=1: Automatic mode (A→B→C state machine)

Manual mode (PUB002):
- MotorForward activates with ForwardButton when Mode=0, interlocked with ReverseButton
- MotorReverse activates with ReverseButton when Mode=0, interlocked with ForwardButton
- CompletionLight always OFF in manual mode

Automatic mode (PUB003):
- IDLE→SensorA: wait at Station A for ButtonA press
- Station A: MotorForward TRUE while State=MOVING_TO_B
- MOVING_TO_B→SensorB: hold at Station B for ButtonB press
- Station B: MotorForward TRUE while State=MOVING_TO_C
- MOVING_TO_C→SensorC: hold at Station C

CompletionLight behavior (PUB006, PUB007, PUB008):
- Activation: State=STATION_C AND SensorC AND ButtonC (same-scan)
- Retention: State=STATION_C AND SensorC (CompletionLight remains TRUE)
- Deactivation: State≠STATION_C OR NOT SensorC (product removal)
- Units: boolean, no units

Output states:
- MotorForward: combinational in manual, pulsed in auto (A→B, B→C transitions)
- MotorReverse: combinational in manual only, always FALSE in auto
- CompletionLight: retained while product at Station C, no explicit reset input

Scan priority: same-scan evaluation of all conditions before outputs
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK ProductionLineControl
VAR_INPUT
    Mode            : BOOL;
    ForwardButton   : BOOL;
    ReverseButton   : BOOL;
    SensorA         : BOOL;
    SensorB         : BOOL;
    SensorC         : BOOL;
    ButtonA         : BOOL;
    ButtonB         : BOOL;
    ButtonC         : BOOL;
END_VAR
VAR_OUTPUT
    MotorForward    : BOOL;
    MotorReverse    : BOOL;
    CompletionLight : BOOL;
END_VAR
VAR
    State : INT;
END_VAR

// State constants
CONSTANTS
    STATE_IDLE         : INT := 0;
    STATE_STATION_A    : INT := 1;
    STATE_MOVING_TO_B  : INT := 2;
    STATE_STATION_B    : INT := 3;
    STATE_MOVING_TO_C  : INT := 4;
    STATE_STATION_C    : INT := 5;
END_CONSTANTS

// Initialize state on first call
IF State = 0 THEN
    State := STATE_IDLE;
END_IF

// Manual mode: direct button control with direction interlock
IF Mode = FALSE THEN
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
    CompletionLight := FALSE;
    State := STATE_IDLE;
ELSE
    // Automatic mode: state machine control
    IF State = STATE_IDLE THEN
        MotorForward := FALSE;
        MotorReverse := FALSE;
        CompletionLight := FALSE;
        
        IF SensorA THEN
            State := STATE_STATION_A;
        END_IF
        
    ELSIF State = STATE_STATION_A THEN
        MotorForward := FALSE;
        
        IF ButtonA THEN
            State := STATE_MOVING_TO_B;
        END_IF
        
    ELSIF State = STATE_MOVING_TO_B THEN
        MotorForward := TRUE;
        
        IF SensorB THEN
            MotorForward := FALSE;
            State := STATE_STATION_B;
        END_IF
        
    ELSIF State = STATE_STATION_B THEN
        MotorForward := FALSE;
        
        IF ButtonB THEN
            State := STATE_MOVING_TO_C;
        END_IF
        
    ELSIF State = STATE_MOVING_TO_C THEN
        MotorForward := TRUE;
        
        IF SensorC THEN
            MotorForward := FALSE;
            State := STATE_STATION_C;
        END_IF
        
    ELSIF State = STATE_STATION_C THEN
        MotorForward := FALSE;
        
        IF NOT SensorC THEN
            State := STATE_IDLE;
            CompletionLight := FALSE;
        ELSE
            CompletionLight := TRUE;
        END_IF
    END_IF
END_IF

END_FUNCTION_BLOCK