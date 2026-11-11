FUNCTION_BLOCK AlarmHandling
VAR_INPUT
    Value : REAL;
    hiLevel : REAL;
    loLevel : REAL;
    hystWindow : REAL;
END_VAR
VAR_OUTPUT
    hiAlarm : BOOL;
    loAlarm : BOOL;
    error : BOOL;
    status : WORD;
END_VAR
VAR
    hiActive : BOOL := FALSE;
    loActive : BOOL := FALSE;
END_VAR

    error := FALSE;
    status := WORD#0;

    // 错误条件：loLevel 大于或等于 hiLevel
    IF loLevel >= hiLevel THEN
        error := TRUE;
        status := WORD#16#8001;
        RETURN;
    END_IF;

    // 错误条件：hystWindow 大于或等于高低限差值
    IF hystWindow >= (hiLevel - loLevel) THEN
        error := TRUE;
        status := WORD#16#8002;
        RETURN;
    END_IF;

    // 高报警迟滞逻辑
    IF Value > hiLevel THEN
        hiActive := TRUE;
    ELSIF Value < (hiLevel - hystWindow) THEN
        hiActive := FALSE;
    END_IF;

    // 低报警迟滞逻辑
    IF Value < loLevel THEN
        loActive := TRUE;
    ELSIF Value > (loLevel + hystWindow) THEN
        loActive := FALSE;
    END_IF;

    hiAlarm := hiActive;
    loAlarm := loActive;

END_FUNCTION_BLOCK