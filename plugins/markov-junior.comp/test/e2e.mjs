import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import assert from 'node:assert/strict'
import { compileMjirV1FromXml, initialGrid } from './mjir-v1.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(here, '../../..')
const plugin = join(repoRoot, 'build.nosync/plugins/markov-junior.comp.wasm')
const basicXml = '<one values="BW" in="B" out="W"/>'

function invokeMarkov(target, args) {
  const result = spawnSync('cargo', [
    'run',
    '--quiet',
    '--manifest-path',
    'cmd/app/src-tauri/Cargo.toml',
    '--',
    'run',
    '--plug',
    plugin,
    target,
    JSON.stringify(args),
  ], {
    cwd: repoRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      ...process.env,
      GAMS_APP_CWD: join(repoRoot, 'examples/demo'),
      GAMS_WASMTIME_CACHE_DIR: join(repoRoot, 'build.nosync/wasmtime-cache-e2e/markov-junior.comp'),
      CARGO_TARGET_DIR: join(repoRoot, 'build.nosync/app/target'),
    },
  })

  assert.equal(result.status, 0, `${result.stderr}\n${result.stdout}`)
  return JSON.parse(result.stdout)
}

function runMarkov(modelIr, initialCells, config) {
  return invokeMarkov('markov-junior/markov-junior::run', [modelIr, initialCells, config])
}

const result = runMarkov(
  compileMjirV1FromXml(basicXml),
  initialGrid(3, 2, 1, 0),
  { width: 3, height: 2, depth: 1, seed: 42, 'max-steps': 10 },
)

assert.equal(result.err, undefined, result.err)
assert.deepEqual(result.ok, {
  width: 3,
  height: 2,
  depth: 1,
  values: 'BW',
  cells: [1, 1, 1, 1, 1, 1],
  'steps-run': 6,
  changed: true,
  done: true,
})

const partial = runMarkov(
  compileMjirV1FromXml(basicXml),
  initialGrid(3, 2, 1, 0),
  { width: 3, height: 2, depth: 1, seed: 42, 'max-steps': 2 },
)

assert.equal(partial.err, undefined, partial.err)
assert.equal(partial.ok.cells.filter((cell) => cell === 1).length, 2)
assert.equal(partial.ok.cells.filter((cell) => cell === 0).length, 4)
assert.equal(partial.ok['steps-run'], 2)
assert.equal(partial.ok.done, false)

const connectExitsXml = readFileSync(join(repoRoot, 'examples/demo/ng/markov/connect-exits.xml'), 'utf8')
const connectExits = runMarkov(
  compileMjirV1FromXml(connectExitsXml),
  [
    0, 0, 0, 0, 0, 0, 0,
    0, 2, 1, 1, 1, 2, 0,
    0, 0, 0, 0, 0, 0, 0,
  ],
  { width: 7, height: 3, depth: 1, seed: 1, 'max-steps': 50 },
)

assert.equal(connectExits.err, undefined, connectExits.err)
assert.equal(connectExits.ok.values, 'XBDSP')
assert.equal(connectExits.ok.cells.filter((cell) => cell === 2).length, 0, 'all door candidates should be consumed when there are two exits')
assert.equal(connectExits.ok.cells.filter((cell) => cell === 3).length, 2, 'both exits become connected entrances')
assert.equal(connectExits.ok.cells.filter((cell) => cell === 4).length, 3, 'path connects exits')
assert.equal(connectExits.ok.done, true)

console.log('markov-junior.comp e2e ok')
