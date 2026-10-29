#!/usr/bin/env bash
# dsh-yu-kit —— macOS / Linux 安装脚本
#
# ⚠️ 这份脚本作者没有在真机上跑过（作者只有 Windows）。逻辑和 install.ps1 一致：
#    装插件 → 验证 profile → 打印手动步骤；不覆盖用户配置和人格。
#    跑挂了请把报错贴到 issue。
set -euo pipefail

PROFILE="desktop"
SKIP_PLUGINS=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --skip-plugins) SKIP_PLUGINS=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE_DIR="$DSH_HOME/profiles/$PROFILE"

step() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  + %s\n' "$1"; }
warn() { printf '  ! %s\n' "$1"; }

# --- 1. 找 dsh CLI -----------------------------------------------------------
if command -v dsh >/dev/null 2>&1; then
  DSH_BIN="$(command -v dsh)"
  ok "dsh: $DSH_BIN"
elif [[ -x "/Applications/DeepSeek Harness.app/Contents/MacOS/DeepSeek Harness" ]]; then
  warn "只找到桌面版，没找到 dsh CLI。"
  warn "桌面版的 CLI 在 app.asar 里，用 bash 不好调 —— 请先把 dsh 装进 PATH："
  warn "  npm i -g @deepseek-ai/dsh    # 或者从 DSH 仓库里 link"
  exit 1
else
  warn "找不到 dsh。先装 DSH 再跑这个脚本。"
  exit 1
fi

echo
echo "DSH_HOME : $DSH_HOME"
echo "profile  : $PROFILE"
[[ $DRY_RUN -eq 1 ]] && echo && echo "(这是 dry-run，不改任何东西)"

# --- 2. 装插件 ---------------------------------------------------------------
# 清单在 plugins.json 里；这里用 node 读，避免再引一个 yaml 解析器。
if [[ $SKIP_PLUGINS -eq 1 ]]; then
  step "跳过插件安装（--skip-plugins）"
else
  step "装插件（10 个，版本钉死）"
  if ! command -v node >/dev/null 2>&1; then
    warn "需要 node 来读 plugins.json。装个 node 再跑。"
    exit 1
  fi
  while IFS=$'\t' read -r name source; do
    echo "  -> $name"
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  [dry-run] dsh plugin --profile $PROFILE add $source"
    else
      if ! dsh plugin --profile "$PROFILE" add "$source"; then
        warn "$name 安装失败；为避免把半安装状态误报为成功，脚本停止。修好后直接重跑："
        warn "  dsh plugin --profile $PROFILE add $source"
        exit 1
      fi
    fi
  done < <(node -e '
    const k = require(process.argv[1]);
    for (const p of k.plugins) console.log(p.name + "\t" + p.source);
  ' "$ROOT/plugins.json")
fi
[[ $DRY_RUN -eq 1 ]] && ok "dry-run 计划检查完成（未实际安装）"

# --- 4. 验证 profile ----------------------------------------------------------
step "验证插件清单"
if [[ $DRY_RUN -eq 0 ]]; then
  node - "$ROOT/plugins.json" "$PROFILE_DIR/package.json" <<'NODE'
const fs = require('fs')
const kit = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const pkg = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const deps = new Set(Object.keys(pkg.dependencies || {}))
const bundles = new Set(pkg.dsh?.profile?.bundles || [])
const missing = kit.plugins.filter((p) => !deps.has(p.name) || !bundles.has(p.name)).map((p) => p.name)
if (missing.length) throw new Error('依赖或 bundle 缺少：' + missing.join(', '))
for (const plugin of kit.plugins) {
  const meta = JSON.parse(fs.readFileSync(process.argv[3].replace(/package\.json$/, '') + 'node_modules/' + plugin.name + '/package.json', 'utf8'))
  if (meta.version !== plugin.version) throw new Error(`${plugin.name}=${meta.version}，需要 ${plugin.version}`)
}
NODE
  if [[ ! -e "$PROFILE_DIR/.plugin-manager" ]]; then dsh --profile "$PROFILE" --dump-config >/dev/null; fi
  ok "插件清单与配置树验证通过"
fi

# --- 5. 人格与配置只给指引 ---------------------------------------------------
step "人格与配置"
AGENTS="$DSH_HOME/AGENTS.md"
if [[ -f "$AGENTS" ]]; then
  ok "已有 $AGENTS —— 不动它。"
else
  warn "还没有 $AGENTS；先读 profile/AGENTS.template.md，再由用户确认后复制。"
fi
warn "profile/cordis.patch.template.yml 只作参考；安装器不会覆盖现有 cordis.patch.yml。"

# --- 6. 手动步骤 --------------------------------------------------------------
step "还要你自己动手（脚本做不到）"
node -e '
  const k = require(process.argv[1]);
  let i = 0;
  for (const p of k.plugins) {
    if (!p.manual || !p.manual.length) continue;
    console.log(`  [${++i}] ${p.name}`);
    for (const m of p.manual) console.log(`      - ${m}`);
  }
' "$ROOT/plugins.json"
echo
warn "模型 key 还没填：设置 → 模型。没 key 一句话都说不了。"
warn "人格还没写：那是全套东西里唯一不能自动化的部分。"
warn "完整清单：MANUAL-STEPS.md"

step "装完这样验"
echo "  1) dsh --profile $PROFILE --dump-config   # 能打出配置树就说明插件装上了"
echo "  2) 启动 DSH，左侧应能看到这些插件的设置页"
echo "  3) 设置 → 模型，填 key，随便说一句话"
echo "  4) 只登一个内容源，跑一轮，看它写出来的东西像不像人"
