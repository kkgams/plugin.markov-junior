import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { compileXmlToMjir, initialGridFromXml, parseMjstate } from './mjir-v1.mjs'
import {
  configForModel,
  modelConfigTag,
  parseArgs,
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
const mjRoot = process.env.MARKOV_JUNIOR_REPO ?? resolve(repoRoot, '../MarkovJunior')
const plugin = join(repoRoot, 'build.nosync/plugins/markov-junior.comp.wasm')
const tempRoot = join(repoRoot, 'build.nosync/markov-junior-parity/csharp')
const modelsXml = readFileSync(join(mjRoot, 'models.xml'), 'utf8')

const smokeModels = ['Basic', 'NestedGrowth', 'ForestFire', 'Backtracker', 'MarchingSquares', 'WaveFlowers']
const odinParitySkipModels = new Set(['ModernHouse'])
const supportedModels = [
  ...rootOneModels,
  ...rootAllModels,
  ...rootPrlModels,
  ...rootConvolutionModels,
  ...rootConvChainModels,
  ...rootMarkovModels,
  ...rootSequenceModels,
  ...rootWfcModels,
]

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? repoRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, ...options.env },
    maxBuffer: 128 * 1024 * 1024,
  })
  assert.equal(result.status, 0, `${command} ${args.join(' ')} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  return result.stdout
}

function patchedRunCwd(name, prefix) {
  const configTag = modelConfigTag(name)
  if (!configTag) return mjRoot
  const tempCwd = mkdtempSync(join(tempRoot, `${name}-${prefix}-`))
  symlinkSync(join(mjRoot, 'bin'), join(tempCwd, 'bin'))
  symlinkSync(join(mjRoot, 'models'), join(tempCwd, 'models'))
  symlinkSync(join(mjRoot, 'resources'), join(tempCwd, 'resources'))
  symlinkSync(join(mjRoot, 'source'), join(tempCwd, 'source'))
  symlinkSync(join(mjRoot, 'MarkovJunior.csproj'), join(tempCwd, 'MarkovJunior.csproj'))
  writeFileSync(join(tempCwd, 'models.xml'), modelsXml.replace('</models>', `  ${configTag}\n</models>`))
  return tempCwd
}

function originalRunCwd(name) {
  return patchedRunCwd(name, 'original')
}

function runComponent(modelIr, initialCells, config) {
  mkdirSync(tempRoot, { recursive: true })
  const argsFile = join(tempRoot, `invoke-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.json`)
  writeFileSync(argsFile, JSON.stringify([modelIr, initialCells, config]))
  try {
    const stdout = run('cargo', [
      'run', '--quiet', '--manifest-path', 'cmd/app/src-tauri/Cargo.toml', '--',
      'run', '--plug', plugin, '--args-file', argsFile, 'markov-junior/markov-junior::run',
    ], {
      env: {
        GAMS_APP_CWD: join(repoRoot, 'examples/demo'),
        GAMS_WASMTIME_CACHE_DIR: join(repoRoot, 'build.nosync/wasmtime-cache-e2e/markov-junior-parity-csharp'),
        CARGO_TARGET_DIR: join(repoRoot, 'build.nosync/app/target'),
      },
    })
    const payload = JSON.parse(stdout)
    assert.equal(payload.err, undefined, payload.err)
    return payload.ok
  } finally {
    rmSync(argsFile, { force: true })
  }
}

function assertSameGrid(label, actual, golden) {
  assert.equal(actual.width, golden.width, `${label}: width`)
  assert.equal(actual.height, golden.height, `${label}: height`)
  assert.equal(actual.depth, golden.depth, `${label}: depth`)
  assert.equal(actual.values, golden.values, `${label}: values`)
  assert.equal(actual.cells.length, golden.cells.length, `${label}: cell count`)
  for (let i = 0; i < golden.cells.length; i++) assert.equal(actual.cells[i], golden.cells[i], `${label}: cell ${i}`)
}

function outputs(dir) {
  return readdirSync(dir).filter((entry) => entry.endsWith('.txt')).sort()
}

function runCsharp(name, runs, steps, outDir) {
  rmSync(outDir, { recursive: true, force: true })
  mkdirSync(outDir, { recursive: true })
  run('dotnet', ['run', '--project', 'MarkovJunior.csproj', '--', name, '--model-index=0', `--amount=${runs}`, `--steps=${steps}`, '--format=text', `--output=${outDir}`], { cwd: patchedRunCwd(name, 'csharp') })
}

function runOdin(name, runs, steps, outDir) {
  rmSync(outDir, { recursive: true, force: true })
  mkdirSync(outDir, { recursive: true })
  run('./bin/markovjunior-odin', [name, `--amount=${runs}`, `--steps=${steps}`, '--format=text', `--output=${outDir}`], { cwd: originalRunCwd(name) })
}

function parityModel(name, options) {
  const csDir = join(tempRoot, name, 'csharp')
  const odinDir = join(tempRoot, name, 'odin')
  runCsharp(name, options.runs, options.steps, csDir)
  runOdin(name, options.runs, options.steps, odinDir)

  const csOutputs = outputs(csDir)
  const odinOutputs = outputs(odinDir)
  assert.deepEqual(odinOutputs, csOutputs, `${name}: C# and Odin output files differ`)

  const xml = readFileSync(join(mjRoot, `models/${name}.xml`), 'utf8')
  const config = configForModel(modelsXml, name)
  const modelIr = compileXmlToMjir(xml, {
    depth: config.depth,
    loadSamplePng: (sample) => readFileSync(join(mjRoot, `resources/samples/${sample}.png`)),
    loadRulePng: (file, folder = '') => {
      const path = join(mjRoot, 'resources/rules', folder, `${file}.png`)
      return existsSync(path) ? readFileSync(path) : undefined
    },
    loadRuleVox: (file, folder = '') => {
      const path = join(mjRoot, 'resources/rules', folder, `${file}.vox`)
      return existsSync(path) ? readFileSync(path) : undefined
    },
    loadTilesetXml: (tileset) => {
      const path = join(mjRoot, 'resources/tilesets', `${tileset}.xml`)
      return existsSync(path) ? readFileSync(path, 'utf8') : undefined
    },
    loadTileVox: (tiles, tile) => {
      const path = join(mjRoot, 'resources/tilesets', tiles, `${tile}.vox`)
      return existsSync(path) ? readFileSync(path) : undefined
    },
  })

  for (const output of csOutputs) {
    const csharp = parseMjstate(readFileSync(join(csDir, output), 'utf8'))
    if (!odinParitySkipModels.has(name)) {
      const odin = parseMjstate(readFileSync(join(odinDir, output), 'utf8'))
      assertSameGrid(`${name}/${output}: Odin vs C#`, odin, csharp)
    }
    const seed = Number(output.match(new RegExp(`${name}_(\\d+)\\.txt$`))?.[1])
    assert.ok(Number.isInteger(seed), `${name}: could not extract seed from ${output}`)
    const component = runComponent(
      modelIr,
      initialGridFromXml(xml, config.width, config.height, config.depth),
      { width: config.width, height: config.height, depth: config.depth, seed, 'max-steps': options.steps },
    )
    assertSameGrid(`${name}/${seed}: component vs C#`, component, csharp)
  }
  console.log(`markov-junior C#/Odin/component ${name} parity ok`)
}

function main(argv = process.argv.slice(2)) {
  const group = argv.find((arg) => arg.startsWith('--group='))?.slice('--group='.length) ?? 'smoke'
  const noBuild = argv.includes('--no-build')
  const defaults = { models: group === 'supported' ? supportedModels : smokeModels, runs: 1, steps: 10 }
  const options = parseArgs(argv.filter((arg) => !arg.startsWith('--group=') && arg !== '--no-build'), defaults)
  if (!noBuild) {
    run('make', [plugin])
    run('make', ['odin'], { cwd: mjRoot })
  }
  console.log(`C#/Odin/component parity: models=${options.models.join(',')} runs=${options.runs} steps=${options.steps}`)
  for (const model of options.models) parityModel(model, options)
}

main()
