import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const kit = JSON.parse(readFileSync(join(root, 'plugins.json'), 'utf8'))

test('kit pins eight self plugins and two third-party plugins exactly once', () => {
  assert.equal(kit.plugins.length, 10)
  assert.equal(kit.plugins.filter((p) => p.self).length, 8)
  assert.equal(new Set(kit.plugins.map((p) => p.name)).size, 10)
  for (const plugin of kit.plugins) {
    assert.match(plugin.version, /^\d+\.\d+\.\d+$/)
    if (plugin.self) assert.match(plugin.source, /^github:Speraymer\/[\w-]+#[0-9a-f]{40}$/)
    else assert.equal(plugin.source, `${plugin.name}@${plugin.version}`)
  }
})

test('installers preserve existing profile config and stop on partial install', () => {
  for (const file of ['install.ps1', 'install.sh']) {
    const text = readFileSync(join(root, file), 'utf8')
    assert.doesNotMatch(text, /WriteAllText\(\$patchPath|fs\.writeFileSync\(out|cp .*AGENTS\.template/)
    assert.match(text, /安装校验失败|依赖或 bundle 缺少/)
  }
})

test('public instructions do not hardcode a private install path or direct data deletion', () => {
  const text = ['README.md', 'AGENT-INSTALL.md', 'MANUAL-STEPS.md', 'install.ps1']
    .map((file) => readFileSync(join(root, file), 'utf8')).join('\n')
  assert.doesNotMatch(text, /H:\\DeepSeekHarness/)
  assert.doesNotMatch(text, /删掉 `~\/.dsh`|只删 `global-memory|想清空就删|忘掉一切.*删/)
})
