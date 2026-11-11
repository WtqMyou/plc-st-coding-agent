PROGRAM AerationBlowerControl
VAR_INPUT
    DO_LOW             : BOOL;
    AERATION_E_STOP_NC : BOOL;
END_VAR

VAR_OUTPUT
    BLOWER_RUN                    : BOOL;
    AERATION_BLOWER_CYCLE_COUNT   : UINT := 0;
END_VAR

VAR
    StartTimer    : TON;
    BlowerRunPrev : BOOL := FALSE;
END_VAR

// ---------------------------------------------------------------------------
// Start Delay Logic
// ---------------------------------------------------------------------------
// Conditions for starting: DO is low AND emergency stop is inactive
IF DO_LOW AND AERATION_E_STOP_NC THEN
    // Start the 5-second delay timer
    StartTimer(IN := TRUE, PT := T#5S);
    
    // Enable blower only after timer completes
    IF StartTimer.Q THEN
        BLOWER_RUN := TRUE;
    ELSE
        BLOWER_RUN := FALSE;
    END_IF;
ELSE
    // Conditions not met - immediately disable blower
    BLOWER_RUN := FALSE;
    
    // Reset the start timer
    StartTimer(IN := FALSE);
END_IF;

// ---------------------------------------------------------------------------
// Start Cycle Counting
// Detect FALSE-to-TRUE transition of BLOWER_RUN
// ---------------------------------------------------------------------------
IF BLOWER_RUN AND NOT BlowerRunPrev THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF;

// Store previous state for edge detection
BlowerRunPrev := BLOWER_RUN;

END_PROGRAM