import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import assert from 'node:assert/strict'
import { compileXmlToMjir, initialGridFromXml, parseMjstate } from './mjir-v1.mjs'
import { configForModel, modelConfigTag, parseArgs, rootOneModels } from './root-one-fixtures.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(here, '../../..')
const mjRoot = process.env.MARKOV_JUNIOR_REPO ?? resolve(repoRoot, '../MarkovJunior')
const plugin = join(repoRoot, 'build.nosync/plugins/markov-junior.comp.wasm')
const tempRoot = join(repoRoot, 'build.nosync/markov-junior-parity/root-one')
const modelsXml = readFileSync(join(mjRoot, 'models.xml'), 'utf8')

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
  mkdirSync(tempRoot, { recursive: true })
  const argsFile = join(tempRoot, `invoke-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.json`)
  writeFileSync(argsFile, JSON.stringify([modelIr, initialCells, config]))
  try {
    const stdout = run('cargo', [
      'run',
      '--quiet',
      '--manifest-path',
      'cmd/app/src-tauri/Cargo.toml',
      '--',
      'run',
      '--plug',
      plugin,
      '--args-file',
      argsFile,
      'markov-junior/markov-junior::run',
    ], {
      env: {
        GAMS_APP_CWD: join(repoRoot, 'examples/demo'),
        GAMS_WASMTIME_CACHE_DIR: join(repoRoot, 'build.nosync/wasmtime-cache-e2e/markov-junior-parity'),
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

function assertSameGrid(name, seed, actual, golden) {
  assert.equal(actual.width, golden.width, `${name}/${seed}: width`)
  assert.equal(actual.height, golden.height, `${name}/${seed}: height`)
  assert.equal(actual.depth, golden.depth, `${name}/${seed}: depth`)
  assert.equal(actual.values, golden.values, `${name}/${seed}: values`)
  assert.equal(actual.cells.length, golden.cells.length, `${name}/${seed}: cell count`)
  for (let i = 0; i < golden.cells.length; i++) {
    assert.equal(actual.cells[i], golden.cells[i], `${name}/${seed}: cell ${i}`)
  }
}

function originalRunCwd(name) {
  const configTag = modelConfigTag(name)
  if (!configTag) return mjRoot
  const tempCwd = mkdtempSync(join(tempRoot, `${name}-original-`))
  symlinkSync(join(mjRoot, 'bin'), join(tempCwd, 'bin'))
  symlinkSync(join(mjRoot, 'models'), join(tempCwd, 'models'))
  const patchedModelsXml = modelsXml.replace('</models>', `  ${configTag}\n</models>`)
  writeFileSync(join(tempCwd, 'models.xml'), patchedModelsXml)
  return tempCwd
}

function compileModel(name) {
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
  return { xml, config, modelIr }
}

export function parityModel(name, { runs, steps, seed }) {
  const { xml, config, modelIr } = compileModel(name)

  if (seed !== undefined) {
    const actual = runComponent(
      modelIr,
      initialGridFromXml(xml, config.width, config.height, config.depth),
      { width: config.width, height: config.height, depth: config.depth, seed, 'max-steps': steps },
    )
    assert.equal(actual.width > 0, true, `${name}/${seed}: width`)
    assert.equal(actual.height > 0, true, `${name}/${seed}: height`)
    assert.equal(actual.depth > 0, true, `${name}/${seed}: depth`)
    assert.equal(actual.cells.length, actual.width * actual.height * actual.depth, `${name}/${seed}: cell count`)
    console.log(`markov-junior ${name} seed=${seed} component replay ok`)
    return
  }

  const tempDir = join(tempRoot, name)
  rmSync(tempDir, { recursive: true, force: true })
  mkdirSync(tempDir, { recursive: true })

  const originalCwd = originalRunCwd(name)
  run('./bin/markovjunior-odin', [name, `--amount=${runs}`, `--steps=${steps}`, '--format=text', `--output=${tempDir}`], { cwd: originalCwd })

  const outputs = readdirSync(tempDir).filter((entry) => entry.endsWith('.txt')).sort()
  assert.equal(outputs.length, runs, `${name}: expected ${runs} original outputs, got ${outputs.join(', ')}`)

  for (const output of outputs) {
    const golden = parseMjstate(readFileSync(join(tempDir, output), 'utf8'))
    const seed = Number(output.match(new RegExp(`${name}_(\\d+)\\.txt$`))?.[1])
    assert.ok(Number.isInteger(seed), `${name}: could not extract seed from ${output}`)

    const actual = runComponent(
      modelIr,
      initialGridFromXml(xml, config.width, config.height, config.depth),
      { width: config.width, height: config.height, depth: config.depth, seed, 'max-steps': steps },
    )

    assertSameGrid(name, seed, actual, golden)
    console.log(`markov-junior ${name} seed=${seed} parity ok`)
  }
}

export function originalRepoAvailable(root = mjRoot) {
  return existsSync(join(root, 'odin'))
}

export function skipOrRequireOriginalRepo(options, root = mjRoot) {
  if (originalRepoAvailable(root)) return false
  const message = `MarkovJunior repo not found at ${root}; set MARKOV_JUNIOR_REPO`
  if (!options.skipMissingOriginal) throw new Error(message)
  console.log(`skip parity: ${message}`)
  return true
}

export function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv, { models: rootOneModels, runs: 1, steps: 10 })
  if (skipOrRequireOriginalRepo(options)) return

  run('make', [plugin])
  run('make', ['odin'], { cwd: mjRoot })
  console.log(`root-one parity: models=${options.models.join(',')} runs=${options.runs} steps=${options.steps}`)
  for (const model of options.models) parityModel(model, options)
}

if (import.meta.url === `file://${process.argv[1]}`) main()
