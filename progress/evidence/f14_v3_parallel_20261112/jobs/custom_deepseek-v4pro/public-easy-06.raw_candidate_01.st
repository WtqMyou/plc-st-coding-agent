FUNCTION_BLOCK AerationBlowerDelayedStart
VAR_INPUT
    DO_LOW : BOOL;
    AERATION_E_STOP_NC : BOOL;
END_VAR
VAR_OUTPUT
    BLOWER_RUN : BOOL;
    AERATION_BLOWER_CYCLE_COUNT : UINT;
END_VAR
VAR
    startCondition : BOOL;
    runInternal : BOOL := FALSE;
    countInternal : UINT := 0;
    prevRun : BOOL := FALSE;
    fbTon : TON;
END_VAR

startCondition := DO_LOW AND AERATION_E_STOP_NC;
fbTon(IN := startCondition, PT := T#5s);
runInternal := fbTon.Q;
BLOWER_RUN := runInternal;

IF runInternal AND NOT prevRun THEN
    countInternal := countInternal + 1;
END_IF;
prevRun := runInternal;

AERATION_BLOWER_CYCLE_COUNT := countInternal;
END_FUNCTION_BLOCK