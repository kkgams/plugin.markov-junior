import { spawnSync } from 'node:child_process'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parityModel, skipOrRequireOriginalRepo } from './parity-root-one.mjs'
import { parseArgs, rootAllModels } from './root-one-fixtures.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(here, '../../..')
const mjRoot = process.env.MARKOV_JUNIOR_REPO ?? resolve(repoRoot, '../MarkovJunior')

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? repoRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, ...options.env },
    maxBuffer: 64 * 1024 * 1024,
  })
  if (result.status !== 0) throw new Error(`${command} ${args.join(' ')} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  return result.stdout
}

const options = parseArgs(process.argv.slice(2), { models: rootAllModels, runs: 1, steps: 10 })
if (!skipOrRequireOriginalRepo(options, mjRoot)) {
  run('make', [join(repoRoot, 'build.nosync/plugins/markov-junior.comp.wasm')])
  run('make', ['odin'], { cwd: mjRoot })
  console.log(`root-all parity: models=${options.models.join(',')} runs=${options.runs} steps=${options.steps}`)
  for (const model of options.models) parityModel(model, options)
}
