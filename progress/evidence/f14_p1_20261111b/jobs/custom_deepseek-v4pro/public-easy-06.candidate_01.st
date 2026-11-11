FUNCTION_BLOCK AerationBlowerControl
VAR_INPUT
    DO_LOW : BOOL;
    AERATION_E_STOP_NC : BOOL;
END_VAR
VAR_OUTPUT
    BLOWER_RUN : BOOL;
    AERATION_BLOWER_CYCLE_COUNT : UINT;
END_VAR
VAR
    StartDelay : TON;
    RunRising : R_TRIG;
    bInit : BOOL := TRUE;
END_VAR

// Power-up initialization
IF bInit THEN
    BLOWER_RUN := FALSE;
    AERATION_BLOWER_CYCLE_COUNT := 0;
    bInit := FALSE;
END_IF;

// Start delay: run only while DO is low and emergency stop is inactive.
StartDelay(IN := DO_LOW AND AERATION_E_STOP_NC, PT := T#5s);

// Blower run command follows the completed start delay.
BLOWER_RUN := StartDelay.Q;

// Count each false-to-true transition of the actual run command.
RunRising(CLK := BLOWER_RUN);
IF RunRising.Q THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF;

END_FUNCTION_BLOCK