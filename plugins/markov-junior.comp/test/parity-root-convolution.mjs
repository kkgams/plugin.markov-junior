import { parityModel, skipOrRequireOriginalRepo } from './parity-root-one.mjs'
import { parseArgs, rootConvolutionModels } from './root-one-fixtures.mjs'

const options = parseArgs(process.argv.slice(2), { models: rootConvolutionModels, runs: 1, steps: 10 })
if (!skipOrRequireOriginalRepo(options)) {
  console.log(`root-convolution parity: models=${options.models.join(',')} runs=${options.runs} steps=${options.steps}`)
  for (const name of options.models) parityModel(name, options)
}
