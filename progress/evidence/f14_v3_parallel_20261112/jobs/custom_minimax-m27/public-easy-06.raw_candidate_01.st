FUNCTION_BLOCK AerationBlowerControl
VAR_INPUT
    DO_LOW : BOOL;
    AERATION_E_STOP_NC : BOOL;
END_VAR

VAR_OUTPUT
    BLOWER_RUN : BOOL := FALSE;
    AERATION_BLOWER_CYCLE_COUNT : UINT := 0;
END_VAR

VAR
    StartDelayTimer : TON;
    BlowerRunPrev : BOOL := FALSE;
END_VAR

    // Start delay timing when both DO_LOW and E-stop inactive (NC = TRUE)
    IF DO_LOW AND AERATION_E_STOP_NC THEN
        // Start the 5-second timer
        StartDelayTimer(IN := TRUE, PT := T#5S);
        
        // BLOWER_RUN only TRUE after timer completes
        IF StartDelayTimer.Q THEN
            BLOWER_RUN := TRUE;
        ELSE
            BLOWER_RUN := FALSE;
        END_IF;
    ELSE
        // Conditions lost: reset timer and disable blower
        StartDelayTimer(IN := FALSE);
        BLOWER_RUN := FALSE;
    END_IF;

    // Count FALSE-to-TRUE transitions of BLOWER_RUN
    IF BLOWER_RUN AND NOT BlowerRunPrev THEN
        AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
    END_IF;

    // Store previous state for edge detection
    BlowerRunPrev := BLOWER_RUN;

END_FUNCTION_BLOCK