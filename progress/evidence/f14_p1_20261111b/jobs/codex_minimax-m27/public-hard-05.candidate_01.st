Looking at the requirements, I need to implement a PLC program in Structured Text (ST) for a mechanical arm with 4 operating modes and a preset handling sequence.

Let me first check if there's an AGENTS.md file or any existing project structure:
[TOOL_CALL]
{tool => "ReadFile", args => {
  --file "E:/PLC_Dev/evidence/real_experiments/f14_p1_20261111b/cli_private/1fbdd13952db4ec59f39848f20c42d92/AGENTS.md"
}}
[/TOOL_CALL]
[TOOL_CALL]
{tool => "ListDirectory", args => {
  --path "E:/PLC_Dev/evidence/real_experiments/f14_p1_20261111b/cli_private/1fbdd13952db4ec59f39848f20c42d92"
}}
[/TOOL_CALL]