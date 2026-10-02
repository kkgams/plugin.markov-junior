import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import assert from 'node:assert/strict'
import { compileXmlToMjir, initialGridFromXml } from './mjir-v1.mjs'
import { configForModel, parseArgs, rootOneModels } from './root-one-fixtures.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(here, '../../..')
const mjRoot = process.env.MARKOV_JUNIOR_REPO ?? resolve(repoRoot, '../MarkovJunior')
const plugin = join(repoRoot, 'build.nosync/plugins/markov-junior.comp.wasm')

function randomSeed() {
  return Math.floor(Math.random() * 0x7fffffff)
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? repoRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, ...options.env },
    maxBuffer: 64 * 1024 * 1024,
  })
  assert.equal(result.status, 0, `${command} ${args.join(' ')} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  return result.stdout
}

function runComponent(modelIr, initialCells, config) {
  const stdout = run('cargo', [
    'run',
    '--quiet',
    '--manifest-path',
    'cmd/app/src-tauri/Cargo.toml',
    '--',
    'run',
    '--plug',
    plugin,
    'markov-junior/markov-junior::run',
    JSON.stringify([modelIr, initialCells, config]),
  ], {
    env: {
      GAMS_APP_CWD: join(repoRoot, 'examples/demo'),
      GAMS_WASMTIME_CACHE_DIR: join(repoRoot, 'build.nosync/wasmtime-cache-e2e/markov-junior-fuzz'),
      CARGO_TARGET_DIR: join(repoRoot, 'build.nosync/app/target'),
    },
  })
  const payload = JSON.parse(stdout)
  assert.equal(payload.err, undefined, payload.err)
  return payload.ok
}

function assertGridShape(name, seed, grid, config, values, steps) {
  assert.equal(grid.width, config.width, `${name}/${seed}: width`)
  assert.equal(grid.height, config.height, `${name}/${seed}: height`)
  assert.equal(grid.depth, config.depth, `${name}/${seed}: depth`)
  assert.equal(grid.values, values, `${name}/${seed}: values`)
  assert.equal(grid.cells.length, config.width * config.height * config.depth, `${name}/${seed}: cell count`)
  assert.ok(grid['steps-run'] <= steps, `${name}/${seed}: steps-run ${grid['steps-run']} > ${steps}`)
  for (let i = 0; i < grid.cells.length; i++) {
    assert.ok(grid.cells[i] >= 0 && grid.cells[i] < values.length, `${name}/${seed}: cell ${i} out of range: ${grid.cells[i]}`)
  }
}

function fuzzModel(name, { runs, steps, seed }) {
  const xml = readFileSync(join(mjRoot, `models/${name}.xml`), 'utf8')
  const values = xml.match(/\bvalues="([^"]*)"/)?.[1]?.replaceAll(' ', '')
  if (!values) throw new Error(`${name}: missing values attribute`)

  const config = configForModel(readFileSync(join(mjRoot, 'models.xml'), 'utf8'), name)
  const modelIr = compileXmlToMjir(xml)
  const initial = initialGridFromXml(xml, config.width, config.height, config.depth)

  for (let i = 0; i < runs; i++) {
    const runSeed = seed === undefined ? randomSeed() : seed + i
    const runConfig = { ...config, seed: runSeed, 'max-steps': steps }
    const first = runComponent(modelIr, initial, runConfig)
    const second = runComponent(modelIr, initial, runConfig)

    assert.deepEqual(second, first, `${name}/${runSeed}: deterministic replay failed; reproduce with --model=${name} --runs=1 --steps=${steps} --seed=${runSeed}`)
    assertGridShape(name, runSeed, first, config, values, steps)
    console.log(`markov-junior ${name} seed=${runSeed} fuzz deterministic ok`)
  }
}

const options = parseArgs(process.argv.slice(2), { models: rootOneModels, runs: 10, steps: 10 })
run('make', [plugin])
console.log(`root-one fuzz: models=${options.models.join(',')} runs=${options.runs} steps=${options.steps} seed=${options.seed ?? 'random'}`)
for (const model of options.models) fuzzModel(model, options)
