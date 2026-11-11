<tool_calls>
<invoke name="shell">
<parameter name="command">rg --files -g '*' -g '!*.bin' | select-string -Pattern '\.'</parameter>
</invoke>
</shell>