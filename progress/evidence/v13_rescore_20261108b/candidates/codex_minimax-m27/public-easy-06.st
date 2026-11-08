FUNCTION_BLOCK FB
VAR_INPUT
    DO_LOW : BOOL;
    AERATION_E_STOP_NC : BOOL;
END_VAR
VAR_OUTPUT
    BLOWER_RUN : BOOL;
    AERATION_BLOWER_CYCLE_COUNT : UINT;
END_VAR
VAR
    prev_blower_run : BOOL := FALSE;
    delay_counter : UINT := 0;
END_VAR

IF DO_LOW AND AERATION_E_STOP_NC THEN
    IF delay_counter < 5 THEN
        delay_counter := delay_counter + 1;
    END_IF
    IF delay_counter >= 5 THEN
        BLOWER_RUN := TRUE;
    ELSE
        BLOWER_RUN := FALSE;
    END_IF
ELSE
    BLOWER_RUN := FALSE;
    delay_counter := 0;
END_IF

IF BLOWER_RUN AND NOT prev_blower_run THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF

prev_blower_run := BLOWER_RUN;
END_FUNCTION_BLOCK