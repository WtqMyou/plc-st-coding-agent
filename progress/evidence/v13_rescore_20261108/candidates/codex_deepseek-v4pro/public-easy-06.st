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
    first_scan : BOOL := TRUE;
    delay_counter : UINT;
    blower_run_prev : BOOL;
END_VAR

IF first_scan THEN
    BLOWER_RUN := FALSE;
    AERATION_BLOWER_CYCLE_COUNT := 0;
    delay_counter := 0;
    blower_run_prev := FALSE;
    first_scan := FALSE;
END_IF;

IF DO_LOW AND AERATION_E_STOP_NC THEN
    IF delay_counter < 5 THEN
        delay_counter := delay_counter + 1;
    END_IF;
ELSE
    delay_counter := 0;
    BLOWER_RUN := FALSE;
END_IF;

IF DO_LOW AND AERATION_E_STOP_NC AND delay_counter >= 5 THEN
    BLOWER_RUN := TRUE;
ELSE
    BLOWER_RUN := FALSE;
END_IF;

IF BLOWER_RUN AND NOT blower_run_prev THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF;

blower_run_prev := BLOWER_RUN;

END_FUNCTION_BLOCK