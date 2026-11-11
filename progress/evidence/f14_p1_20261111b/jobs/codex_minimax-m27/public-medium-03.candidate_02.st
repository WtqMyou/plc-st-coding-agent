{"cmd":["Set-Content -Path 'fb_moving_average.st' -Value @'\nFUNCTION_BLOCK FB_MovingAverage\nVAR_INPUT\n    cyclicExecution : BOOL;\n    trigger : BOOL;\n    value : LREAL;\n    windowSize : INT;\n    reset : BOOL;\nEND_VAR\n\nVAR_OUTPUT\n    average : LREAL;\n    windowSizeReached : BOOL;\n    error : BOOL;\n    status : WORD;\nEND_VAR\n\nVAR\n    buffer : ARRAY[1..100] OF LREAL;\n    index : INT := 1;\n    count : INT := 0;\n    sum : LREAL := 0.0;\n    lastTrigger : BOOL := FALSE;\n    i : INT;\nEND_VAR\n\n(* Main logic *)\nIF reset THEN\n    (* Reset all internal state *)\n    index := 1;\n    count := 0;\n    sum := 0.0;\n    average := 0.0;\n    windowSizeReached := FALSE;\n    error := FALSE;\n    status := 16#0000;\n    \n    (* Clear the buffer *)\n    FOR i := 1 TO 100 DO\n        buffer[i] := 0.0;\n    END_FOR;\n    \n    lastTrigger := FALSE;\n    \nELSIF windowSize < 1 OR windowSize > 100 THEN\n    (* Window size validation error *)\n    error := TRUE;\n    status := 16#8200;\n    windowSizeReached := FALSE;\n    \nELSE\n    (* Check for update condition: cyclic execution OR rising edge of trigger *)\n    IF cyclicExecution OR (trigger AND NOT lastTrigger) THEN\n        (* If buffer is full, subtract the oldest value from sum *)\n        (* If buffer not full, just increment count *)\n        IF count >= windowSize THEN\n            sum := sum - buffer[index];\n        ELSE\n            count := count + 1;\n        END_IF;\n        \n        (* Store new value and update sum *)\n        buffer[index] := value;\n        sum := sum + value;\n        \n        (* Calculate average *)\n        average := sum / LREAL_TO_INT(count);\n        \n        (* Update circular buffer index (wrap around) *)\n        index := (index MOD windowSize) + 1;\n        \n        (* Update windowSizeReached flag *)\n        windowSizeReached := (count >= windowSize);\n        \n        (* Clear error status on successful execution *)\n        error := FALSE;\n        status := 16#0000;\n    END_IF;\n    \n    (* Store trigger state for next cycle (rising edge detection) *)\n    lastTrigger := trigger;\nEND_IF;\n\nEND_FUNCTION_BLOCK\n'@"]}
<newline>
</newline>

{"cmd":["Get-Content -Path 'fb_moving_average.st'"]}
<newline>
</newline>

代码已修复，将 `{ }` 注释语法替换为 ST 标准 `(* *)` 注释语法。

**关键修复：**
- 将所有 `{...}` 注释改为 `(*...*)` 格式
- 保持原有逻辑不变：
  - 循环缓冲区管理（index 从 1 到 windowSize 循环）
  - 上升沿检测（lastTrigger）
  - 窗口大小验证（1-100）
  - 复位功能
  - 状态码（16#0000 成功，16#8200 错误）