(* Production Line Control System *)
(* 5 Workstations: Loading → Cleaning → Weighing → Firing → Finished Product *)

PROGRAM ProductionLineControl
VAR
    (* Mode Selection *)
    Mode AT %IX0.0 : BOOL;              (* 0=Manual, 1=Automatic *)
    
    (* Manual Mode Inputs *)
    ForwardButton AT %IX0.1 : BOOL;     (* Forward rotation button *)
    ReverseButton AT %IX0.2 : BOOL;     (* Reverse rotation button *)
    
    (* Automatic Mode - Sensors *)
    SensorFeed AT %IX0.3 : BOOL;        (* Material loading station sensor *)
    SensorWash AT %IX0.4 : BOOL;        (* Cleaning station sensor *)
    SensorWeight AT %IX0.5 : BOOL;      (* Weighing station sensor *)
    SensorFiring AT %IX0.6 : BOOL;      (* Firing station sensor *)
    SensorOutput AT %IX0.7 : BOOL;      (* Finished product station sensor *)
    
    (* Process Completion Signals *)
    washComplete AT %IX1.0 : BOOL;      (* Cleaning complete signal *)
    weightComplete AT %IX1.1 : BOOL;    (* Weighing complete signal *)
    firingComplete AT %IX1.2 : BOOL;    (* Firing complete signal *)
    
    (* Process Values *)
    weight AT %ID2 : REAL;              (* Weight value *)
    
    (* Outputs *)
    MotorForward AT %QX0.0 : BOOL;      (* Motor forward rotation *)
    MotorReverse AT %QX0.1 : BOOL;      (* Motor reverse rotation *)
    kick AT %QX0.2 : BOOL;              (* Rejection output *)
    CompletionLight AT %QX0.3 : BOOL;   (* Completion indicator light *)
    firingTemp AT %QD2 : REAL;          (* Firing temperature *)
    
    (* State Machine Variables *)
    CurrentState : INT;
    PreviousSensorFeed : BOOL;
    PreviousSensorWash : BOOL;
    PreviousSensorWeight : BOOL;
    PreviousSensorFiring : BOOL;
    PreviousSensorOutput : BOOL;
    PreviousWashComplete : BOOL;
    PreviousWeightComplete : BOOL;
    PreviousFiringComplete : BOOL;
    
    (* Edge Detection Flags *)
    SensorFeedEdge : BOOL;
    SensorWashEdge : BOOL;
    SensorWeightEdge : BOOL;
    SensorFiringEdge : BOOL;
    SensorOutputEdge : BOOL;
    WashCompleteEdge : BOOL;
    WeightCompleteEdge : BOOL;
    FiringCompleteEdge : BOOL;
    
    (* Temporary Variables *)
    weightValue : REAL;
    tempCalc : REAL;
END_VAR

(* Constants for States *)
VAR CONSTANT
    STATE_IDLE : INT := 0;
    STATE_FEED_DETECTED : INT := 1;
    STATE_WASH_WAIT : INT := 2;
    STATE_WEIGHING_WAIT : INT := 3;
    STATE_WEIGHT_CHECK : INT := 4;
    STATE_FIRING_WAIT : INT := 5;
    STATE_OUTPUT_WAIT : INT := 6;
END_VAR

(* EDGE DETECTION FOR ALL SENSORS AND SIGNALS *)
SensorFeedEdge := SensorFeed AND NOT PreviousSensorFeed;
SensorWashEdge := SensorWash AND NOT PreviousSensorWash;
SensorWeightEdge := SensorWeight AND NOT PreviousSensorWeight;
SensorFiringEdge := SensorFiring AND NOT PreviousSensorFiring;
SensorOutputEdge := SensorOutput AND NOT PreviousSensorOutput;
WashCompleteEdge := washComplete AND NOT PreviousWashComplete;
WeightCompleteEdge := weightComplete AND NOT PreviousWeightComplete;
FiringCompleteEdge := firingComplete AND NOT PreviousFiringComplete;

(* Update Previous States *)
PreviousSensorFeed := SensorFeed;
PreviousSensorWash := SensorWash;
PreviousSensorWeight := SensorWeight;
PreviousSensorFiring := SensorFiring;
PreviousSensorOutput := SensorOutput;
PreviousWashComplete := washComplete;
PreviousWeightComplete := weightComplete;
PreviousFiringComplete := firingComplete;

(* MANUAL MODE CONTROL *)
IF Mode = FALSE THEN
    (* Interlock: Forward and Reverse cannot be active simultaneously *)
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
    
    (* Reset automatic mode outputs *)
    kick := FALSE;
    CompletionLight := FALSE;
    firingTemp := 0.0;
    
    (* Reset state machine *)
    CurrentState := STATE_IDLE;
END_IF

(* AUTOMATIC MODE CONTROL *)
IF Mode = TRUE THEN
    CASE CurrentState OF
        
        (* STATE_IDLE: Wait for material at loading station *)
        STATE_IDLE:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            kick := FALSE;
            CompletionLight := FALSE;
            firingTemp := 0.0;
            
            (* Material detected at loading station *)
            IF SensorFeedEdge THEN
                CurrentState := STATE_FEED_DETECTED;
            END_IF
        
        (* STATE_FEED_DETECTED: Material detected, start motor to move to cleaning *)
        STATE_FEED_DETECTED:
            MotorForward := TRUE;
            MotorReverse := FALSE;
            kick := FALSE;
            CompletionLight := FALSE;
            
            (* Material reached cleaning station *)
            IF SensorWashEdge THEN
                MotorForward := FALSE;
                CurrentState := STATE_WASH_WAIT;
            END_IF
        
        (* STATE_WASH_WAIT: Material at cleaning station, wait for washComplete *)
        STATE_WASH_WAIT:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            kick := FALSE;
            CompletionLight := FALSE;
            
            (* Cleaning complete, move to weighing *)
            IF WashCompleteEdge THEN
                MotorForward := TRUE;
                CurrentState := STATE_WEIGHING_WAIT;
            END_IF
        
        (* STATE_WEIGHING_WAIT: Material at weighing station, wait for weightComplete *)
        STATE_WEIGHING_WAIT:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            kick := FALSE;
            CompletionLight := FALSE;
            
            (* Weighing complete, check weight *)
            IF WeightCompleteEdge THEN
                CurrentState := STATE_WEIGHT_CHECK;
            END_IF
        
        (* STATE_WEIGHT_CHECK: Evaluate weight and determine qualification *)
        STATE_WEIGHT_CHECK:
            weightValue := weight;
            
            (* Check if weight is within qualified range [100, 200] *)
            IF (weightValue >= 100.0) AND (weightValue <= 200.0) THEN
                (* Qualified product - Calculate firing temperature *)
                (* Linear mapping: weight 100→200 maps to temperature 500→550 *)
                tempCalc := 500.0 + ((weightValue - 100.0) / 100.0) * 50.0;
                firingTemp := tempCalc;
                kick := FALSE;
                
                (* Move to firing station *)
                MotorForward := TRUE;
                MotorReverse := FALSE;
                CurrentState := STATE_FIRING_WAIT;
            ELSE
                (* Unqualified product - Reject *)
                kick := TRUE;
                firingTemp := 0.0;
                MotorForward := FALSE;
                MotorReverse := FALSE;
                
                (* Return to idle after rejection *)
                CurrentState := STATE_IDLE;
            END_IF
        
        (* STATE_FIRING_WAIT: Product at firing station, wait for firingComplete *)
        STATE_FIRING_WAIT:
            kick := FALSE;
            CompletionLight := FALSE;
            
            (* Firing complete, move to finished product station *)
            IF FiringCompleteEdge THEN
                MotorForward := TRUE;
                MotorReverse := FALSE;
                CurrentState := STATE_OUTPUT_WAIT;
            END_IF
        
        (* STATE_OUTPUT_WAIT: Product at finished product station *)
        STATE_OUTPUT_WAIT:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            kick := FALSE;
            
            (* Product detected at output - Turn on completion light *)
            IF SensorOutput THEN
                CompletionLight := TRUE;
            ELSE
                (* Product taken away - Turn off completion light *)
                CompletionLight := FALSE;
                CurrentState := STATE_IDLE;
            END_IF
        
    END_CASE
END_IF

END_PROGRAM