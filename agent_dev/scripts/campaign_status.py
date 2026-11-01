"""Human-readable local status; never sends model requests or changes the budget."""
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
import html
import json
import os
from pathlib import Path


def load(path):
    try:
        return json.loads(Path(path).read_text(encoding='utf-8-sig'))
    except (OSError, ValueError):
        return {}


def registered_process_alive(marker):
    if os.name != 'nt' or not marker.get('pid'):
        return False
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
    handle = kernel.OpenProcess(0x1000, False, int(marker['pid']))
    if not handle:
        return False
    try:
        code = wintypes.DWORD()
        times = [wintypes.FILETIME() for _ in range(4)]
        if not kernel.GetExitCodeProcess(handle, ctypes.byref(code)) or code.value != 259:
            return False
        if not kernel.GetProcessTimes(handle, *(ctypes.byref(value) for value in times)):
            return False
        ticks = (times[0].dwHighDateTime << 32) | times[0].dwLowDateTime
        created = ticks / 10000000 - 11644473600
        expected = datetime.fromisoformat(marker['process_created_at']).timestamp()
        return abs(created - expected) < 1
    finally:
        kernel.CloseHandle(handle)


def write_status(campaign, cfg):
    campaign = Path(campaign)
    finish = load(campaign / 'finish_status.json')
    exited = load(campaign / 'runner_exit.json')
    marker = load(campaign / 'active_run.json')
    alive = registered_process_alive(marker)
    paused = finish.get('state') == 'paused_by_user' or marker.get('state') == 'paused'
    if paused:
        title = '实验已按你的要求暂停'
    elif finish.get('state') == 'completed':
        title = '实验及归档全部完成'
    elif finish.get('state') == 'needs_diagnosis' or exited.get('state') == 'stopped':
        title = '实验已停止，需要检查'
    elif exited.get('state') == 'completed':
        title = '实验运行结束，正在生成报告与验收包'
    elif alive:
        title = '实验正在运行'
    else:
        title = '实验进程未运行，需要检查'
    lines = [title, '', '更新时间：' + datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %Z'), '']
    labels = [('pilot', '代表题', 24), ('develop_round_1', '策略开发第 1 轮', 12),
              ('develop_round_2', '策略开发第 2 轮', 12), ('develop_round_3', '策略开发第 3 轮', 12),
              ('final', '四组正式评测', 140), ('retest', '可选消融复测', 12)]
    for stage, label, total in labels:
        folder = campaign / stage
        count = sum(bool(load(p).get('attempts')) for p in folder.glob('*/*.json')
                    if not p.name.endswith(('.timing.json', '.openplc.json')))
        lines.append(f'{label}：已保存 {count}/{total} 个题次记录' + ('（尚未开始）' if not folder.exists() else ''))
    reused = load(campaign / 'pilot_reuse.json').get('records', 0)
    if reused:
        lines += ['', f'代表题中 {reused} 条沿用已经付费的历史记录，不重复计费。']
    budget = load(cfg['budget_ledger_path'])
    if budget:
        lines += ['', f"共享账本累计计入：{budget['spent_cny']:.4f} / 75 元（含保留费用，非平台实际账单）。"]
    lines += ['', '题次记录包含失败；数量完成不代表所有题目通过。']
    if alive:
        lines += ['电脑需保持开机联网，不要手动睡眠、休眠或关机；可以关闭显示器。']
    elif paused:
        lines += ['可以断网、合盖或关机。换好地方后，开机联网并告诉我“继续实验”再恢复。',
                  '已有结果与费用记录已保留；当前不会自动恢复或产生新的请求。']
    if finish.get('reports'):
        lines += ['', '报告位置：' + finish['reports']]
    if finish.get('package'):
        lines += ['最终工程包：' + finish['package']]
    if not paused and (finish.get('error') or exited.get('error')):
        lines += ['', '停止原因：' + str(finish.get('error') or exited['error'])]
    text = '\n'.join(lines) + '\n'
    document = ('<!doctype html><html lang="zh-CN"><meta charset="utf-8">'
                '<meta http-equiv="refresh" content="15"><title>实验状态</title>'
                '<style>body{font:17px/1.8 system-ui,sans-serif;max-width:980px;margin:40px auto;padding:0 24px;'
                'color:#18324a;background:#f6f8fb}pre{white-space:pre-wrap;overflow-wrap:anywhere;'
                'font:inherit;background:white;padding:28px;border-radius:12px}</style><pre>' +
                html.escape(text) + '</pre><p>页面每 15 秒刷新；请核对上方更新时间。</p></html>')
    for name, content in [('实验状态.txt', text), ('实验状态.html', document)]:
        path = campaign / name
        temporary = path.with_suffix(path.suffix + '.tmp')
        temporary.write_text(content, encoding='utf-8')
        temporary.replace(path)
    return alive
