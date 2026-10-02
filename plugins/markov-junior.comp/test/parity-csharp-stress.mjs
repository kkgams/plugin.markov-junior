import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  parseList,
  rootAllModels,
  rootConvolutionModels,
  rootConvChainModels,
  rootMarkovModels,
  rootOneModels,
  rootPrlModels,
  rootSequenceModels,
  rootWfcModels,
} from './root-one-fixtures.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(here, '../../..')
const defaultLog = join(repoRoot, 'build.nosync/markov-junior-parity/csharp-stress/stress.jsonl')
const plugin = join(repoRoot, 'build.nosync/plugins/markov-junior.comp.wasm')
const allSupportedModels = [
  ...rootOneModels,
  ...rootAllModels,
  ...rootPrlModels,
  ...rootConvolutionModels,
  ...rootConvChainModels,
  ...rootMarkovModels,
  ...rootSequenceModels,
  ...rootWfcModels,
]
const smokeModels = ['Basic', 'NestedGrowth', 'ForestFire', 'Backtracker', 'MarchingSquares', 'WaveFlowers', 'TileDungeon']

function usage() {
  return `usage: node plugins/markov-junior.comp/test/parity-csharp-stress.mjs [options]

Options:
  --group=smoke|supported       default: supported
  --models=A,B,C                explicit model list
  --steps=10,50,100             comma-separated step counts; default: 10,50,100
  --runs=N                      C#/Odin amount per model/steps case; default: 3
  --log=PATH                    JSONL progress log; default: ${defaultLog}
  --no-resume                   rerun cases already marked pass in log
  --keep-going                  continue after failures
  --no-build                    skip initial component/Odin builds

Each case is one model + one step count + --runs=N. Passing cases are skipped on restart unless --no-resume is set.
`
}

function parseArgs(argv) {
  const options = {
    group: 'supported',
    models: undefined,
    steps: [10, 50, 100],
    runs: 3,
    log: defaultLog,
    resume: true,
    keepGoing: false,
    build: true,
  }
  for (const arg of argv) {
    if (arg === '--help' || arg === '-h') {
      console.log(usage())
      process.exit(0)
    } else if (arg.startsWith('--group=')) options.group = arg.slice('--group='.length)
    else if (arg.startsWith('--models=')) options.models = parseList(arg.slice('--models='.length))
    else if (arg.startsWith('--model=')) options.models = [arg.slice('--model='.length)]
    else if (arg.startsWith('--steps=')) options.steps = parseList(arg.slice('--steps='.length)).map(Number)
    else if (arg.startsWith('--runs=')) options.runs = Number(arg.slice('--runs='.length))
    else if (arg.startsWith('--log=')) options.log = resolve(arg.slice('--log='.length))
    else if (arg === '--no-resume') options.resume = false
    else if (arg === '--keep-going') options.keepGoing = true
    else if (arg === '--no-build') options.build = false
    else throw new Error(`unknown argument: ${arg}`)
  }
  if (options.group !== 'smoke' && options.group !== 'supported') throw new Error(`invalid --group: ${options.group}`)
  if (!Number.isInteger(options.runs) || options.runs <= 0) throw new Error(`invalid --runs: ${options.runs}`)
  for (const steps of options.steps) if (!Number.isInteger(steps) || steps < 0) throw new Error(`invalid --steps entry: ${steps}`)
  return options
}

function run(command, args, options = {}) {
  const startedAt = Date.now()
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? repoRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, ...options.env },
    maxBuffer: 512 * 1024 * 1024,
  })
  return { ...result, durationMs: Date.now() - startedAt }
}

function appendJsonl(path, record) {
  mkdirSync(dirname(path), { recursive: true })
  appendFileSync(path, `${JSON.stringify({ time: new Date().toISOString(), ...record })}\n`)
}

function passedKeys(path) {
  const keys = new Set()
  if (!existsSync(path)) return keys
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (!line.trim()) continue
    const record = JSON.parse(line)
    if (record.status === 'pass') keys.add(record.key)
  }
  return keys
}

function safeName(value) {
  return value.replace(/[^A-Za-z0-9_.-]/g, '_')
}

function formatDuration(ms) {
  if (!Number.isFinite(ms) || ms < 0) return 'unknown'
  const totalSeconds = Math.round(ms / 1000)
  const seconds = totalSeconds % 60
  const totalMinutes = Math.floor(totalSeconds / 60)
  const minutes = totalMinutes % 60
  const hours = Math.floor(totalMinutes / 60)
  if (hours > 0) return `${hours}h ${minutes}m ${seconds}s`
  if (minutes > 0) return `${minutes}m ${seconds}s`
  return `${seconds}s`
}

function progressLine({ caseIndex, totalCases, model, steps, runs, skipped, completed, failures, startedAt, measuredCases, measuredMs }) {
  const elapsedMs = Date.now() - startedAt
  const percent = totalCases === 0 ? 100 : (caseIndex / totalCases) * 100
  const remainingCases = totalCases - caseIndex
  const avgMeasuredMs = measuredCases > 0 ? measuredMs / measuredCases : undefined
  const etaMs = avgMeasuredMs === undefined ? undefined : avgMeasuredMs * remainingCases
  return `[${caseIndex}/${totalCases} ${percent.toFixed(1)}%] model=${model} steps=${steps} runs=${runs} completed=${completed} skipped=${skipped} failures=${failures} elapsed=${formatDuration(elapsedMs)} eta=${formatDuration(etaMs)}`
}

function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv)
  const models = options.models ?? (options.group === 'smoke' ? smokeModels : allSupportedModels)
  const passed = options.resume ? passedKeys(options.log) : new Set()
  const logDir = dirname(options.log)
  mkdirSync(logDir, { recursive: true })

  if (options.build) {
    for (const [command, args, cwd] of [
      ['make', [plugin], repoRoot],
      ['make', ['odin'], process.env.MARKOV_JUNIOR_REPO ?? resolve(repoRoot, '../MarkovJunior')],
    ]) {
      const result = run(command, args, { cwd })
      assert.equal(result.status, 0, `${command} ${args.join(' ')} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
    }
  }

  const totalCases = models.length * options.steps.length
  const startedAt = Date.now()
  console.log(`C#/Odin/component stress: models=${models.length} steps=${options.steps.join(',')} runs=${options.runs} cases=${totalCases} log=${options.log}`)
  appendJsonl(options.log, { status: 'run-start', models: models.length, steps: options.steps, runs: options.runs, totalCases })

  let failures = 0
  let skipped = 0
  let completed = 0
  let caseIndex = 0
  let measuredCases = 0
  let measuredMs = 0
  for (const model of models) {
    for (const steps of options.steps) {
      caseIndex += 1
      const key = `${model}|steps=${steps}|runs=${options.runs}`
      const repro = `nix develop -c node plugins/markov-junior.comp/test/parity-csharp.mjs --model=${model} --runs=${options.runs} --steps=${steps}`
      const progress = () => progressLine({ caseIndex, totalCases, model, steps, runs: options.runs, skipped, completed, failures, startedAt, measuredCases, measuredMs })
      if (passed.has(key)) {
        skipped += 1
        console.log(`${progress()} skip ${key}`)
        continue
      }

      console.log(`${progress()} test ${key}`)
      appendJsonl(options.log, { status: 'start', key, model, steps, runs: options.runs, caseIndex, totalCases, repro })
      const result = run(process.execPath, [
        join(here, 'parity-csharp.mjs'),
        '--no-build',
        `--model=${model}`,
        `--runs=${options.runs}`,
        `--steps=${steps}`,
      ])
      const outPath = join(logDir, `${safeName(model)}-steps${steps}-runs${options.runs}.out`)
      const errPath = join(logDir, `${safeName(model)}-steps${steps}-runs${options.runs}.err`)
      writeFileSync(outPath, result.stdout)
      writeFileSync(errPath, result.stderr)

      measuredCases += 1
      measuredMs += result.durationMs
      if (result.status === 0) {
        completed += 1
        appendJsonl(options.log, { status: 'pass', key, model, steps, runs: options.runs, caseIndex, totalCases, durationMs: result.durationMs, elapsedMs: Date.now() - startedAt, stdout: outPath, stderr: errPath, repro })
        console.log(`${progress()} pass ${key} duration=${formatDuration(result.durationMs)} avg=${formatDuration(measuredMs / measuredCases)}`)
      } else {
        failures += 1
        appendJsonl(options.log, { status: 'fail', key, model, steps, runs: options.runs, caseIndex, totalCases, durationMs: result.durationMs, elapsedMs: Date.now() - startedAt, code: result.status, stdout: outPath, stderr: errPath, repro })
        console.error(`${progress()} FAIL ${key} duration=${formatDuration(result.durationMs)} avg=${formatDuration(measuredMs / measuredCases)}`)
        console.error(`repro: ${repro}`)
        console.error(`stdout: ${outPath}`)
        console.error(`stderr: ${errPath}`)
        if (!options.keepGoing) {
          appendJsonl(options.log, { status: 'run-stop', failures, skipped, completed, caseIndex, totalCases, elapsedMs: Date.now() - startedAt })
          process.exit(result.status || 1)
        }
      }
    }
  }

  appendJsonl(options.log, { status: failures === 0 ? 'run-pass' : 'run-fail', failures, skipped, completed, totalCases, elapsedMs: Date.now() - startedAt, averageCaseMs: measuredCases > 0 ? measuredMs / measuredCases : undefined })
  console.log(`stress done: completed=${completed} skipped=${skipped} failures=${failures} elapsed=${formatDuration(Date.now() - startedAt)} avg=${formatDuration(measuredCases > 0 ? measuredMs / measuredCases : undefined)}`)
  if (failures > 0) process.exit(1)
}

main()
