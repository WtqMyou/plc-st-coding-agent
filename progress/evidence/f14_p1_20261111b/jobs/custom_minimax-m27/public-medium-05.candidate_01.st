// Automated Production Line Control - ST Implementation

// Define the states for automatic mode
TYPE ProductionState :
(
    WAIT_A           := 0,  // Waiting for product at Workstation A
    WAIT_A_PRESSED   := 1,  // Product at A, waiting for ButtonA press
    MOVING_AB        := 2,  // Motor moving product from A to B
    WAIT_B_PRESSED   := 3,  // Product at B, waiting for ButtonB press
    MOVING_BC        := 4,  // Motor moving product from B to C
    WAIT_C_PRESSED   := 5,  // Product at C, waiting for ButtonC press
    COMPLETE         := 6   // Product processing complete
);
END_TYPE

VAR
    // State variable for automatic mode
    State : ProductionState := WAIT_A;
    
    // Edge detection variables
    SensorA_Edge  : BOOL := FALSE;
    SensorB_Edge  : BOOL := FALSE;
    SensorC_Edge  : BOOL := FALSE;
    SensorA_Prev  : BOOL := FALSE;
    SensorB_Prev  : BOOL := FALSE;
    SensorC_Prev  : BOOL := FALSE;
END_VAR

// Edge detection for sensors
SensorA_Edge := SensorA AND NOT SensorA_Prev;
SensorB_Edge := SensorB AND NOT SensorB_Prev;
SensorC_Edge := SensorC AND NOT SensorC_Prev;

// Store previous sensor states for edge detection
SensorA_Prev := SensorA;
SensorB_Prev := SensorB;
SensorC_Prev := SensorC;

// Manual Mode (Mode = 0)
IF Mode = FALSE THEN
    // Reset state to initial when switching to manual mode
    State := WAIT_A;
    
    // Forward and reverse rotation with interlock
    // Both cannot be active at the same time
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
    
    // Completion light is off in manual mode
    CompletionLight := FALSE;
    
// Automatic Mode (Mode = 1)
ELSE
    // State machine logic
    CASE State OF
        // State 0: Waiting for product at Workstation A
        WAIT_A:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            // Detect product arrival at A
            IF SensorA_Edge THEN
                State := WAIT_A_PRESSED;
            END_IF
        
        // State 1: Product at A, waiting for operator to press ButtonA
        WAIT_A_PRESSED:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            // Operator presses ButtonA to signal processing complete
            IF ButtonA THEN
                State := MOVING_AB;
            END_IF
            
            // Safety: If product leaves A unexpectedly, return to WAIT_A
            IF NOT SensorA THEN
                State := WAIT_A;
            END_IF
        
        // State 2: Motor moving product from A to B
        MOVING_AB:
            MotorForward := TRUE;
            MotorReverse := FALSE;
            
            // Product arrives at B
            IF SensorB THEN
                State := WAIT_B_PRESSED;
            END_IF
        
        // State 3: Product at B, waiting for operator to press ButtonB
        WAIT_B_PRESSED:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            // Operator presses ButtonB to signal processing complete
            IF ButtonB THEN
                State := MOVING_BC;
            END_IF
            
            // Safety: If product leaves B unexpectedly, return to WAIT_A
            IF NOT SensorB THEN
                State := WAIT_A;
            END_IF
        
        // State 4: Motor moving product from B to C
        MOVING_BC:
            MotorForward := TRUE;
            MotorReverse := FALSE;
            
            // Product arrives at C
            IF SensorC THEN
                State := WAIT_C_PRESSED;
            END_IF
        
        // State 5: Product at C, waiting for operator to press ButtonC
        WAIT_C_PRESSED:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            // Operator presses ButtonC to signal processing complete
            IF ButtonC THEN
                State := COMPLETE;
            END_IF
            
            // Safety: If product leaves C unexpectedly, return to WAIT_A
            IF NOT SensorC THEN
                State := WAIT_A;
            END_IF
        
        // State 6: Product processing complete
        COMPLETE:
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            // When product is taken away (SensorC no longer detects product)
            IF NOT SensorC THEN
                State := WAIT_A;
            END_IF
    
    END_CASE;
    
    // Set CompletionLight based on current state
    // Light is ON when product is at C and processing is complete (button pressed)
    CompletionLight := (State = COMPLETE);
    
END_IF;