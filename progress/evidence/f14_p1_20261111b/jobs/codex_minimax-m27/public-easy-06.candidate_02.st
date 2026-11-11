FUNCTION_BLOCK AerationBlower
VAR_INPUT
    do_low               : BOOL;
    aeration_e_stop_nc   : BOOL;
END_VAR

VAR_OUTPUT
    blower_run                   : BOOL;
    aeration_blower_cycle_count  : UINT;
END_VAR

VAR
    start_timer        : TON;
    blower_was_running : BOOL;
END_VAR

// Start delay: timer runs while both conditions are met
start_timer(
    IN := do_low AND aeration_e_stop_nc,
    PT := T#5S
);

// Blower runs only when timer elapsed AND conditions remain satisfied
blower_run := start_timer.Q AND do_low AND aeration_e_stop_nc;

// Count FALSE-to-TRUE transitions of blower_run (rising edge)
IF blower_run AND NOT blower_was_running THEN
    aeration_blower_cycle_count := aeration_blower_cycle_count + 1;
END_IF;

// Update edge-detection state for next scan
blower_was_running := blower_run;

END_FUNCTION_BLOCK