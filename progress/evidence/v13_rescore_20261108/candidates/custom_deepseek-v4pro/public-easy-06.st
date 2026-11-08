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
    timer_count : UINT := 0;
    last_run : BOOL := FALSE;
    run_cmd : BOOL := FALSE;
    cycle_count : UINT := 0;
END_VAR

IF DO_LOW AND AERATION_E_STOP_NC THEN
    IF timer_count < 5 THEN
        timer_count := timer_count + 1;
    END_IF;
ELSE
    timer_count := 0;
END_IF;

run_cmd := DO_LOW AND AERATION_E_STOP_NC AND (timer_count >= 5);

IF run_cmd AND NOT last_run THEN
    cycle_count := cycle_count + 1;
END_IF;

BLOWER_RUN := run_cmd;
AERATION_BLOWER_CYCLE_COUNT := cycle_count;
last_run := run_cmd;

END_FUNCTION_BLOCK