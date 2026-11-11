FUNCTION_BLOCK ProductionLineControl
VAR_INPUT
    Mode            : BOOL;   // 0=manual mode, 1=automatic mode
    ForwardButton   : BOOL;   // Forward rotation button
    ReverseButton   : BOOL;   // Reverse rotation button
    SensorA         : BOOL;   // Sensor A
    SensorB         : BOOL;   // Sensor B
    SensorC         : BOOL;   // Sensor C
    ButtonA         : BOOL;   // Button A
    ButtonB         : BOOL;   // Button B
    ButtonC         : BOOL;   // Button C
END_VAR

VAR_OUTPUT
    MotorForward    : BOOL;   // Motor forward rotation output
    MotorReverse    : BOOL;   // Motor reverse rotation output
    CompletionLight : BOOL;   // Indicator light for product processing completion
END_VAR

VAR
    State           : INT := 0;  // 0=WAIT_A, 1=WAIT_A_PRESSED, 2=MOVING_AB, 3=WAIT_B_PRESSED, 4=MOVING_BC, 5=WAIT_C_PRESSED, 6=COMPLETE
    SensorA_Prev    : BOOL := FALSE;
    SensorB_Prev    : BOOL := FALSE;
    SensorC_Prev    : BOOL := FALSE;
END_VAR

// Edge detection for sensors
VAR
    SensorA_Edge    : BOOL;
    SensorB_Edge    : BOOL;
    SensorC_Edge    : BOOL;
END_VAR

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
    State := 0;
    
    // Forward and reverse rotation with interlock
    MotorForward := ForwardButton AND NOT ReverseButton;
    MotorReverse := ReverseButton AND NOT ForwardButton;
    
    // Completion light is off in manual mode
    CompletionLight := FALSE;
    
// Automatic Mode (Mode = 1)
ELSE
    // State machine logic
    CASE State OF
        // State 0: Waiting for product at Workstation A
        0:  // WAIT_A
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            // Detect product arrival at A
            IF SensorA_Edge THEN
                State := 1;
            END_IF
        
        // State 1: Product at A, waiting for operator to press ButtonA
        1:  // WAIT_A_PRESSED
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            // Operator presses ButtonA to signal processing complete
            IF ButtonA THEN
                State := 2;
            END_IF
            
            // Safety: If product leaves A unexpectedly, return to WAIT_A
            IF NOT SensorA THEN
                State := 0;
            END_IF
        
        // State 2: Motor moving product from A to B
        2:  // MOVING_AB
            MotorForward := TRUE;
            MotorReverse := FALSE;
            
            // Product arrives at B
            IF SensorB THEN
                State := 3;
            END_IF
        
        // State 3: Product at B, waiting for operator to press ButtonB
        3:  // WAIT_B_PRESSED
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            // Operator presses ButtonB to signal processing complete
            IF ButtonB THEN
                State := 4;
            END_IF
            
            // Safety: If product leaves B unexpectedly, return to WAIT_A
            IF NOT SensorB THEN
                State := 0;
            END_IF
        
        // State 4: Motor moving product from B to C
        4:  // MOVING_BC
            MotorForward := TRUE;
            MotorReverse := FALSE;
            
            // Product arrives at C
            IF SensorC THEN
                State := 5;
            END_IF
        
        // State 5: Product at C, waiting for operator to press ButtonC
        5:  // WAIT_C_PRESSED
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            // Operator presses ButtonC to signal processing complete
            IF ButtonC THEN
                State := 6;
            END_IF
            
            // Safety: If product leaves C unexpectedly, return to WAIT_A
            IF NOT SensorC THEN
                State := 0;
            END_IF
        
        // State 6: Product processing complete
        6:  // COMPLETE
            MotorForward := FALSE;
            MotorReverse := FALSE;
            
            // When product is taken away (SensorC no longer detects product)
            IF NOT SensorC THEN
                State := 0;
            END_IF
    
    END_CASE;
    
    // Set CompletionLight based on current state
    CompletionLight := (State = 6);
    
END_IF;

END_FUNCTION_BLOCK