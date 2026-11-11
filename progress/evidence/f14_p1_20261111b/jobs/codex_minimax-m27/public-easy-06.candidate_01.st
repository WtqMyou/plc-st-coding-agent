PROGRAM AerationBlower
VAR
    // Inputs
    DO_LOW               : BOOL;  // Dissolved oxygen below threshold
    AERATION_E_STOP_NC   : BOOL;  // TRUE = E-stop inactive, FALSE = E-stop active
    
    // Outputs
    BLOWER_RUN                     : BOOL;  // Blower motor run command
    AERATION_BLOWER_CYCLE_COUNT    : UINT;  // Count of actual blower starts
    
    // Internal variables
    start_timer        : TON;      // On-delay timer for 5-second start delay
    blower_was_running : BOOL;     // Previous cycle state for edge detection
END_VAR

// Start delay: timer runs while both conditions are met
start_timer(
    IN := DO_LOW AND AERATION_E_STOP_NC,
    PT := T#5S
);

// Blower runs only when timer elapsed AND conditions remain satisfied
BLOWER_RUN := start_timer.Q AND DO_LOW AND AERATION_E_STOP_NC;

// Count FALSE-to-TRUE transitions of BLOWER_RUN (rising edge)
IF BLOWER_RUN AND NOT blower_was_running THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF;

// Update edge-detection state for next scan
blower_was_running := BLOWER_RUN;

END_PROGRAM