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
    StartDelayCount : UINT;
    PrevRun : BOOL;
    RunRising : BOOL;
    FirstScan : BOOL;
END_VAR

IF NOT FirstScan THEN
    StartDelayCount := 0;
    PrevRun := FALSE;
    AERATION_BLOWER_CYCLE_COUNT := 0;
    BLOWER_RUN := FALSE;
    FirstScan := TRUE;
END_IF;

IF AERATION_E_STOP_NC AND DO_LOW THEN
    IF StartDelayCount < 5 THEN
        StartDelayCount := StartDelayCount + 1;
    END_IF;

    IF StartDelayCount >= 5 THEN
        BLOWER_RUN := TRUE;
    ELSE
        BLOWER_RUN := FALSE;
    END_IF;
ELSE
    StartDelayCount := 0;
    BLOWER_RUN := FALSE;
END_IF;

RunRising := BLOWER_RUN AND NOT PrevRun;

IF RunRising AND AERATION_BLOWER_CYCLE_COUNT < 65535 THEN
    AERATION_BLOWER_CYCLE_COUNT := AERATION_BLOWER_CYCLE_COUNT + 1;
END_IF;

PrevRun := BLOWER_RUN;

END_FUNCTION_BLOCK