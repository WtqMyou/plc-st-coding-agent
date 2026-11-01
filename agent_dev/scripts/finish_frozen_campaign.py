"""Collect immutable reports after this frozen run exits; never issue model requests."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from stbench.campaign import configuration, digest
from stbench.evaluation import atomic_json
from campaign_status import write_status,registered_process_alive,load


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--wait', action='store_true')
    ap.add_argument('--validation', type=Path, required=True)
    args = ap.parse_args()
    cfg = configuration('')
    campaign = Path(cfg['campaign_root'])
    label = campaign.name.rsplit('_', 1)[-1].upper()
    source = digest()
    deadline = time.monotonic() + 48 * 3600
    while load(campaign / 'runner_exit.json').get('state') not in ('completed', 'stopped'):
        write_status(campaign,cfg)
        if not args.wait:
            raise RuntimeError('Campaign is still running')
        if time.monotonic() >= deadline:
            raise RuntimeError('Report collector wait limit reached; inspect the registered process')
        marker=load(campaign/'active_run.json')
        if marker and not registered_process_alive(marker):
            raise RuntimeError('Registered experiment process disappeared; inspect retained reservations before restarting')
        time.sleep(15)
    if source != digest():
        raise RuntimeError('Source changed while waiting for reports')
    exit_state = json.loads((campaign / 'runner_exit.json').read_text(encoding='utf-8'))
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    out = ROOT / 'evidence' / (label.lower()+'_finished_' + stamp)
    out.mkdir(exist_ok=False)

    def run(name, arguments):
        with (out / (name + '.log')).open('x', encoding='utf-8') as log:
            result = subprocess.run([sys.executable, '-B', '-X', 'utf8'] + arguments,
                                    cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=600)
        if result.returncode:
            raise RuntimeError('Report operation failed: ' + name)

    for stage in ('pilot', 'develop_round_1', 'develop_round_2', 'develop_round_3', 'final', 'retest'):
        if (campaign / stage / 'freeze.json').exists():
            run('analyze_' + stage, ['scripts/analyze_campaign.py', '--stage', stage,
                                     '--out', str(out / stage)])
    analysis_path = out / 'final' / 'analysis.json'
    complete = (exit_state.get('state') == 'completed' and analysis_path.exists() and
                json.loads(analysis_path.read_text(encoding='utf-8')).get('all_tasks_attempted'))
    marker = campaign / 'active_run.json'
    if marker.exists():
        state = json.loads(marker.read_text(encoding='utf-8-sig'))
        state.update(state='completed' if complete else 'stopped', runner_exit=exit_state)
        atomic_json(marker, state)
    if not complete:
        atomic_json(campaign / 'finish_status.json', dict(state='needs_diagnosis', reports=str(out),
                    runner_exit=exit_state, notice='Partial results only; no final package or further model calls'))
        print('Run stopped; partial reports saved:', out, flush=True)
        write_status(campaign,cfg)
        return 2
    analysis = json.loads(analysis_path.read_text(encoding='utf-8'))
    lines = ['# 四组正式实验交付记录', '', '四组各 35 题均实际尝试，固定每组 435 条用例。候选失败和截断保留在完整分母中。', '',
             '逐组结果见 final/report.md、metrics.csv、comparison.png；代表题见 pilot/report.md。若有开发轮次或无 LTL 提示消融，其同名目录单独保留；这些阶段仅运行自研两组，不能补入正式分母。', '',
             '## 同模型下两框架的观测差异', '']
    for model in ('deepseek-v4pro', 'minimax-m27'):
        rows = {r['framework']: r for r in analysis['rows'] if r['model_id'] == model}
        own, baseline = rows['custom'], rows['codex']
        lines.append(f"- {model}：自研整题通过 {own['whole_problem_solved']}/35，Codex {baseline['whole_problem_solved']}/35；"
                     f"自研相差 {own['whole_problem_solved']-baseline['whole_problem_solved']:+d} 题。"
                     f"已返回费用估计分别 {own['known_cost_cny']:.4f} / {baseline['known_cost_cny']:.4f} 元；"
                     f"活动耗时分别 {own['wall_seconds']/60:.2f} / {baseline['wall_seconds']/60:.2f} 分钟。")
    lines += ['', '本比较只描述本次 35 题、给定模型设置和预算下的观测，不主张普遍优势或统计显著性。活动耗时包含生成、裁判、平台检查和框架开销。', '',
              '## 解释边界', '',
              '- CODESYS/OpenPLC 为本机真实编译；功能用例由扫描解释器执行，未部署物理 PLC。',
              '- bounded_pass 仅为有限域和有限深度内结论；截断、超时、未判定与环境外反例不能计为通过。',
              '- FIFO 每条轨迹固定容量 2 或 4；不宣称支持运行中缩容或任意泛型容量。',
              '- 供应商返回用量乘配置单价是费用估计，历史未知预留仍在共享账本；不是供应商实际账单。',
              f"- 代表题中 {load(campaign/'pilot_reuse.json').get('records',0)} 条付费记录兼容复用；正式 140 个题次全部在 {label} 新生成。",
              '- 策略开发与正式评测分目录留痕；35 题是课程全量题库，不应称为未见过的独立测试集。',
              '- 选出的成功工程只供演示，不能替代四组全量汇总。五道新工业题的工艺合理性仍需组内评审。', '']
    (out / '交付说明.md').write_text('\n'.join(lines), encoding='utf-8')
    projects = ROOT / 'platform_projects' / ('live_'+label.lower()+'_final_' + stamp)
    run('collect_projects', ['scripts/collect_live_projects.py', '--stage', 'final', '--out', str(projects)])
    package = ROOT.parent / ('成员2_Agent正式实验工程包_v3.0_'+label+'_' + stamp + '.zip')
    run('package', ['scripts/package_continuation.py', '--kind', 'final', '--analysis', str(analysis_path),
                   '--out', str(package), '--validation', str(args.validation.resolve()),
                   '--include-evidence', str(out), '--include-projects', str(projects)])
    run('verify_package', ['scripts/verify_handoff.py', str(package)])
    atomic_json(campaign / 'finish_status.json', dict(state='completed', reports=str(out), projects=str(projects),
                package=str(package), qa=str(package.with_suffix('.qa.json')), source_sha256=source,
                note='Full formal coverage; model failures and verification limits retained'))
    print('Full formal results and independently verified package ready:', package, flush=True)
    write_status(campaign,cfg)
    return 0


if __name__ == '__main__':
    try:
        result=main()
    except Exception as error:
        cfg=configuration('');campaign=Path(cfg['campaign_root'])
        atomic_json(campaign/'finish_status.json',dict(state='needs_diagnosis',error=str(error),
                    notice='Report collector stopped; no automatic model retry'))
        write_status(campaign,cfg)
        raise
    raise SystemExit(result)
