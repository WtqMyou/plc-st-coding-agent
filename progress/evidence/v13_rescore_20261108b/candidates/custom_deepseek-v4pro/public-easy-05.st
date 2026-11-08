FUNCTION_BLOCK FB
VAR_INPUT
    Gap_Exceeded : BOOL;
    Weld_E_Stop_NC : BOOL;
    DebounceTime : TIME;
END_VAR
VAR_OUTPUT
    Operator_Alert : BOOL;
    Weld_Soft_Start_Active : BOOL;
END_VAR
VAR
    init_count : DINT := 0;
    debounce_count : DINT := 0;
    InitPeriods : DINT := 5;
    DebouncePeriods : DINT;
END_VAR

DebouncePeriods := TIME_TO_DINT(DebounceTime);
IF DebouncePeriods < 3 THEN
    DebouncePeriods := 3;
END_IF;

Weld_Soft_Start_Active := (init_count < InitPeriods);

IF init_count < InitPeriods THEN
    init_count := init_count + 1;
END_IF;

IF NOT Weld_E_Stop_NC THEN
    Operator_Alert := FALSE;
    debounce_count := 0;
ELSE
    IF Weld_Soft_Start_Active THEN
        Operator_Alert := FALSE;
        debounce_count := 0;
    ELSE
        IF Gap_Exceeded THEN
            IF debounce_count < DebouncePeriods THEN
                debounce_count := debounce_count + 1;
            END_IF;
            IF debounce_count >= DebouncePeriods THEN
                Operator_Alert := TRUE;
            ELSE
                Operator_Alert := FALSE;
            END_IF;
        ELSE
            debounce_count := 0;
            Operator_Alert := FALSE;
        END_IF;
    END_IF;
END_IF;

END_FUNCTION_BLOCK