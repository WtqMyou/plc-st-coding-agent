(* =====================================================================
   public-medium-08  IPv4 Parsing with Format and Range Checks
   ---------------------------------------------------------------------
   平台边界（《公共题制作约定》§7）：LEN / 字符串下标 / STRING_TO_INT 可用，
   因此本解按字符扫描实现，不依赖任何 TIME 或结构体能力。

   实现约定（需求原文未逐字规定、此处显式声明的解释）：
   * 段内前导 0（"01"、"00"）按畸形处理 —— 点分十进制的规范写法里
     多位数不允许前导 0；单独一个 "0" 合法。
   * 合法点分十进制最长 15 字符（"255.255.255.255"），超长直接判非法。
   * 任何判非法的情况都把 ipValue 写成 0（需求 3）。
   ===================================================================== *)
FUNCTION_BLOCK FB_Ipv4Parser
VAR_INPUT
  ipText : STRING(254);   (* 待解析的点分十进制文本 *)
END_VAR
VAR_OUTPUT
  ipValue : UDINT;        (* 网络字节序的 32 位地址；非法输入为 0 *)
END_VAR
VAR
  s : STRING(256);        (* ipText 末尾补一个 '.'，让"最后一段"和其余段共用同一收尾逻辑 *)
  n : INT;
  i : INT;
  ch : STRING(1);
  isDigit : BOOL;
  digit : INT;
  segLen : INT;           (* 当前段已读入的数字字符数 *)
  segVal : INT;           (* 当前段的十进制值 *)
  segZeroOnly : BOOL;     (* 当前段是否"只由前导 0 开头" *)
  segCount : INT;         (* 已经收尾的段数 *)
  segments : ARRAY[0..3] OF INT;
  ok : BOOL;              (* 合法性结论（内部观察量） *)
  run : BOOL;
END_VAR

s := CONCAT(ipText, '.');
n := LEN(s);
ok := TRUE;
segCount := 0;
segLen := 0;
segVal := 0;
segZeroOnly := FALSE;

(* R1 / R3: 合法点分十进制最长 15 字符；超长直接判非法 *)
IF LEN(ipText) > 15 THEN
  ok := FALSE;
END_IF;

(* R1: 逐字符扫描，'.' 收尾一段，其余必须是十进制数字 *)
FOR i := 1 TO 16 DO
  run := ok AND (i <= n);
  IF run THEN
    ch := s[i];
    isDigit := (ch >= '0') AND (ch <= '9');
    IF ch = '.' THEN
      IF segLen = 0 THEN
        ok := FALSE;            (* R3: 空段（空输入 / 连续点 / 以点结尾） *)
      ELSIF segLen > 3 THEN
        ok := FALSE;            (* R3: 段内数字超过 3 位 *)
      ELSIF segVal > 255 THEN
        ok := FALSE;            (* R3: 段值超出 0~255 *)
      ELSIF segCount > 3 THEN
        ok := FALSE;            (* R3: 段数超过 4 *)
      ELSE
        segments[segCount] := segVal;
        segCount := segCount + 1;
      END_IF;
      segLen := 0;
      segVal := 0;
      segZeroOnly := FALSE;
    ELSIF isDigit THEN
      digit := STRING_TO_INT(ch);
      IF (segLen = 0) AND (digit = 0) THEN
        segZeroOnly := TRUE;    (* 段首是 0：只允许单独一个 "0" *)
      ELSIF segZeroOnly THEN
        ok := FALSE;            (* R3: 前导 0（"01"/"00"）视为畸形 *)
      END_IF;
      IF segLen < 3 THEN
        segLen := segLen + 1;
        segVal := segVal * 10 + digit;
      ELSE
        segLen := 4;            (* 超过 3 位，留到收尾分支判非法 *)
      END_IF;
    ELSE
      ok := FALSE;              (* R3: 非数字、非点字符（空格、字母、符号…） *)
    END_IF;
  END_IF;
END_FOR;

(* R1 / R3: 必须恰好四段 *)
IF ok AND (segCount <> 4) THEN
  ok := FALSE;
END_IF;

(* R2: 网络字节序拼装（第一段占最高 8 位）；R3: 非法输入 → 0（0.0.0.0 也是 0） *)
ipValue := 0;
IF ok THEN
  FOR i := 0 TO 3 DO
    ipValue := ipValue * 256 + segments[i];
  END_FOR;
END_IF;

END_FUNCTION_BLOCK
