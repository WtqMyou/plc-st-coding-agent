(* Automated Production Line Control *)
(* Three workstations (A→B→C) with manual/automatic mode *)

(* Variable Declarations *)
VAR
    (* Inputs *)
    Mode            : BOOL;  (* 0=Manual, 1=Automatic *)
    ForwardButton   : BOOL;
    ReverseButton   : BOOL;
    SensorA         : BOOL;
    SensorB         : BOOL;
    SensorC         : BOOL;
    ButtonA         : BOOL;
    ButtonB         : BOOL;
    ButtonC         : BOOL;
    
    (* Outputs *)
    MotorForward    : BOOL;
    MotorReverse    : BOOL;
    CompletionLight : BOOL;
    
    (* Internal Variables *)
    State           : INT;
END_VAR

(* State Definitions *)
(* 0: IDLE            - Initial/reset state *)
(* 1: AT_STATION_A    - Product at A, waiting for button *)
(* 2: MOVING_TO_B     - Motor moving product from A to B *)
(* 3: AT_STATION_B    - Product at B, waiting for button *)
(* 4: MOVING_TO_C     - Motor moving product from B to C *)
(* 5: AT_STATION_C    - Product at C, waiting for button *)
(* 6: COMPLETE        - Processing complete, light on *)

(* Initialize outputs to OFF *)
MotorForward    := FALSE;
MotorReverse    := FALSE;
CompletionLight := FALSE;

(* MODE SELECTION *)
IF Mode = FALSE THEN
    (* MANUAL MODE *)
    (* Forward and reverse are interlocked - cannot run simultaneously *)
    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
        MotorReverse := FALSE;
    ELSIF ReverseButton AND NOT ForwardButton THEN
        MotorForward := FALSE;
        MotorReverse := TRUE;
    ELSE
        MotorForward := FALSE;
        MotorReverse := FALSE;
    END_IF
    
    (* Reset state machine when switching to manual *)
    State := 0;
    
ELSE
    (* AUTOMATIC MODE *)
    (* State Machine *)
    CASE State OF
        
        0: (* IDLE - Waiting for product at Station A *)
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            IF SensorA THEN
                State := 1;  (* Product arrived at A *)
            END_IF
            
        1: (* AT STATION A - Waiting for ButtonA *)
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            IF ButtonA THEN
                State := 2;  (* Start moving to B *)
            END_IF
            
        2: (* MOVING TO B - Motor forward *)
            MotorForward := TRUE;
            MotorReverse := FALSE;
            
            (* Stop when product reaches B *)
            IF SensorB THEN
                MotorForward := FALSE;
                State := 3;
            END_IF
            
        3: (* AT STATION B - Waiting for ButtonB *)
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            IF ButtonB THEN
                State := 4;  (* Start moving to C *)
            END_IF
            
        4: (* MOVING TO C - Motor forward *)
            MotorForward := TRUE;
            MotorReverse := FALSE;
            
            (* Stop when product reaches C *)
            IF SensorC THEN
                MotorForward := FALSE;
                State := 5;
            END_IF
            
        5: (* AT STATION C - Waiting for ButtonC *)
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            IF ButtonC THEN
                CompletionLight := TRUE;
                State := 6;  (* Process complete *)
            END_IF
            
        6: (* COMPLETE - Light on until product removed *)
            MotorForward := FALSE;
            MotorReverse := FALSE;
            CompletionLight := TRUE;
            
            (* Turn off light when product is taken away *)
            IF NOT SensorC THEN
                CompletionLight := FALSE;
                State := 0;  (* Return to idle for next product *)
            END_IF
            
    END_CASE
END_IF