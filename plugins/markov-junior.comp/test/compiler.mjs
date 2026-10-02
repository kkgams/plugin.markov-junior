import assert from 'node:assert/strict'
import {
  compileXmlToMjir,
  encodeMjirV1,
  initialGrid,
  initialGridFromXml,
  parseMjstate,
  parsePattern,
  xmlAttr,
  xmlBoolAttr,
  xmlChildNodeTags,
  xmlDirectChildTags,
  xmlRootTag,
  xmlRootStartTag,
  xmlRuleTags,
  xmlUnionTags,
} from '../compiler/xml-to-mjir.mjs'

function readU32(bytes, pos) {
  return bytes[pos] | (bytes[pos + 1] << 8) | (bytes[pos + 2] << 16) | (bytes[pos + 3] << 24)
}

function readF64(bytes, pos) {
  const view = new DataView(Uint8Array.from(bytes.slice(pos, pos + 8)).buffer)
  return view.getFloat64(0, true)
}

function decodeMjirV1(bytes) {
  let pos = 0
  assert.equal(String.fromCharCode(...bytes.slice(pos, pos + 4)), 'MJIR')
  pos += 4
  const version = readU32(bytes, pos); pos += 4
  const valuesLen = readU32(bytes, pos); pos += 4
  const values = String.fromCharCode(...bytes.slice(pos, pos + valuesLen)); pos += valuesLen
  const ruleCount = readU32(bytes, pos); pos += 4
  const rules = []
  const nodes = []
  for (let i = 0; i < ruleCount; i++) {
    const op = readU32(bytes, pos); pos += 4
    if (op === 100) {
      nodes.push({ kind: readU32(bytes, pos), steps: readU32(bytes, pos + 4) }); pos += 8
      continue
    }
    if (op === 101) {
      const symbol = String.fromCharCode(bytes[pos]); pos += 1
      const valuesLen = readU32(bytes, pos); pos += 4
      const unionValues = String.fromCharCode(...bytes.slice(pos, pos + valuesLen)); pos += valuesLen
      rules.push({ op, symbol, values: unionValues })
      continue
    }
    if (op === 102) {
      rules.push({ op })
      continue
    }
    if (op === 103) {
      const forSymbol = String.fromCharCode(bytes[pos]); pos += 1
      const recompute = readU32(bytes, pos) !== 0; pos += 4
      const essential = readU32(bytes, pos) !== 0; pos += 4
      const toLen = readU32(bytes, pos); pos += 4
      const to = String.fromCharCode(...bytes.slice(pos, pos + toLen)); pos += toLen
      const fromLen = readU32(bytes, pos); pos += 4
      const from = String.fromCharCode(...bytes.slice(pos, pos + fromLen)); pos += fromLen
      const onLen = readU32(bytes, pos); pos += 4
      const on = String.fromCharCode(...bytes.slice(pos, pos + onLen)); pos += onLen
      rules.push({ op, for: forSymbol, recompute, essential, to, from, on })
      continue
    }
    if (op === 104) {
      const temperature = readF64(bytes, pos); pos += 8
      rules.push({ op, temperature })
      continue
    }
    if (op === 105) {
      const value = String.fromCharCode(bytes[pos]); pos += 1
      const fromLen = readU32(bytes, pos); pos += 4
      const from = String.fromCharCode(...bytes.slice(pos, pos + fromLen)); pos += fromLen
      const toLen = readU32(bytes, pos); pos += 4
      const to = String.fromCharCode(...bytes.slice(pos, pos + toLen)); pos += toLen
      rules.push({ op, value, from, to })
      continue
    }
    if (op === 111) {
      const enabled = readU32(bytes, pos) !== 0; pos += 4
      const limitRaw = readU32(bytes, pos); pos += 4
      const limit = limitRaw === -1 ? -1 : limitRaw
      const depthCoefficient = readF64(bytes, pos); pos += 8
      rules.push({ op, enabled, limit, depthCoefficient })
      continue
    }
    if (op === 107) {
      const neighborhoodLen = readU32(bytes, pos); pos += 4
      const neighborhood = String.fromCharCode(...bytes.slice(pos, pos + neighborhoodLen)); pos += neighborhoodLen
      const periodic = readU32(bytes, pos) !== 0; pos += 4
      const ruleCount = readU32(bytes, pos); pos += 4
      const convolutionRules = []
      for (let ri = 0; ri < ruleCount; ri++) {
        const input = String.fromCharCode(bytes[pos]); pos += 1
        const output = String.fromCharCode(bytes[pos]); pos += 1
        const probability = readF64(bytes, pos); pos += 8
        const valuesLen = readU32(bytes, pos); pos += 4
        const values = String.fromCharCode(...bytes.slice(pos, pos + valuesLen)); pos += valuesLen
        const sumLen = readU32(bytes, pos); pos += 4
        const sum = String.fromCharCode(...bytes.slice(pos, pos + sumLen)); pos += sumLen
        convolutionRules.push({ input, output, probability, values, sum })
      }
      rules.push({ op, neighborhood, periodic, rules: convolutionRules })
      continue
    }
    if (op === 108) {
      const n = readU32(bytes, pos); pos += 4
      const temperature = readF64(bytes, pos); pos += 8
      const black = String.fromCharCode(bytes[pos]); pos += 1
      const white = String.fromCharCode(bytes[pos]); pos += 1
      const on = String.fromCharCode(bytes[pos]); pos += 1
      const weightCount = readU32(bytes, pos); pos += 4
      const weights = []
      for (let wi = 0; wi < weightCount; wi++) { weights.push(readF64(bytes, pos)); pos += 8 }
      rules.push({ op, n, temperature, black, white, on, weights })
      continue
    }
    if (op === 110) {
      const sx = { n: readU32(bytes, pos), d: readU32(bytes, pos + 4) }; pos += 8
      const sy = { n: readU32(bytes, pos), d: readU32(bytes, pos + 4) }; pos += 8
      const sz = { n: readU32(bytes, pos), d: readU32(bytes, pos + 4) }; pos += 8
      const valuesLen = readU32(bytes, pos); pos += 4
      const mapValues = String.fromCharCode(...bytes.slice(pos, pos + valuesLen)); pos += valuesLen
      const unionCount = readU32(bytes, pos); pos += 4
      const unions = []
      for (let ui = 0; ui < unionCount; ui++) {
        const symbol = String.fromCharCode(bytes[pos]); pos += 1
        const len = readU32(bytes, pos); pos += 4
        const values = String.fromCharCode(...bytes.slice(pos, pos + len)); pos += len
        unions.push({ symbol, values })
      }
      const ruleCount = readU32(bytes, pos); pos += 4
      const mapRules = []
      for (let ri = 0; ri < ruleCount; ri++) {
        const imx = readU32(bytes, pos); pos += 4
        const imy = readU32(bytes, pos); pos += 4
        const imz = readU32(bytes, pos); pos += 4
        const omx = readU32(bytes, pos); pos += 4
        const omy = readU32(bytes, pos); pos += 4
        const omz = readU32(bytes, pos); pos += 4
        const probability = readF64(bytes, pos); pos += 8
        const symmetryLen = readU32(bytes, pos); pos += 4
        const symmetry = String.fromCharCode(...bytes.slice(pos, pos + symmetryLen)); pos += symmetryLen
        const inputLen = imx * imy * imz
        const outputLen = omx * omy * omz
        const input = String.fromCharCode(...bytes.slice(pos, pos + inputLen)); pos += inputLen
        const output = String.fromCharCode(...bytes.slice(pos, pos + outputLen)); pos += outputLen
        mapRules.push({ imx, imy, imz, omx, omy, omz, probability, symmetry, input, output })
      }
      rules.push({ op, sx, sy, sz, values: mapValues, unions, rules: mapRules })
      continue
    }
    if (op === 109) {
      const n = readU32(bytes, pos); pos += 4
      const periodic = readU32(bytes, pos) !== 0; pos += 4
      const shannon = readU32(bytes, pos) !== 0; pos += 4
      const tries = readU32(bytes, pos); pos += 4
      const valuesLen = readU32(bytes, pos); pos += 4
      const wfcValues = String.fromCharCode(...bytes.slice(pos, pos + valuesLen)); pos += valuesLen
      const patternCount = readU32(bytes, pos); pos += 4
      const patterns = []
      const weights = []
      for (let pi = 0; pi < patternCount; pi++) {
        weights.push(readF64(bytes, pos)); pos += 8
        patterns.push([...bytes.slice(pos, pos + n * n)]); pos += n * n
      }
      const dirs = readU32(bytes, pos); pos += 4
      const propagator = []
      for (let d = 0; d < dirs; d++) {
        const dir = []
        for (let pi = 0; pi < patternCount; pi++) {
          const listLen = readU32(bytes, pos); pos += 4
          const list = []
          for (let li = 0; li < listLen; li++) { list.push(readU32(bytes, pos)); pos += 4 }
          dir.push(list)
        }
        propagator.push(dir)
      }
      const mapCount = readU32(bytes, pos); pos += 4
      const maps = []
      for (let mi = 0; mi < mapCount; mi++) {
        const input = String.fromCharCode(bytes[pos]); pos += 1
        const positions = []
        for (let pi = 0; pi < patternCount; pi++) positions.push(bytes[pos++] !== 0)
        maps.push({ input, positions })
      }
      rules.push({ op, n, periodic, shannon, tries, values: wfcValues, patterns, weights, propagator, maps })
      continue
    }
    if (op === 106) {
      const fromLen = readU32(bytes, pos); pos += 4
      const from = String.fromCharCode(...bytes.slice(pos, pos + fromLen)); pos += fromLen
      const toLen = readU32(bytes, pos); pos += 4
      const to = String.fromCharCode(...bytes.slice(pos, pos + toLen)); pos += toLen
      const onLen = readU32(bytes, pos); pos += 4
      const on = String.fromCharCode(...bytes.slice(pos, pos + onLen)); pos += onLen
      const color = String.fromCharCode(bytes[pos]); pos += 1
      const inertia = readU32(bytes, pos) !== 0; pos += 4
      const longest = readU32(bytes, pos) !== 0; pos += 4
      const edges = readU32(bytes, pos) !== 0; pos += 4
      const vertices = readU32(bytes, pos) !== 0; pos += 4
      rules.push({ op, from, to, on, color, inertia, longest, edges, vertices })
      continue
    }
    const imx = readU32(bytes, pos); pos += 4
    const imy = readU32(bytes, pos); pos += 4
    const imz = readU32(bytes, pos); pos += 4
    const omx = readU32(bytes, pos); pos += 4
    const omy = readU32(bytes, pos); pos += 4
    const omz = readU32(bytes, pos); pos += 4
    const probability = readF64(bytes, pos); pos += 8
    const symmetryLen = readU32(bytes, pos); pos += 4
    const symmetry = String.fromCharCode(...bytes.slice(pos, pos + symmetryLen)); pos += symmetryLen
    const inputLen = imx * imy * imz
    const outputLen = omx * omy * omz
    const input = String.fromCharCode(...bytes.slice(pos, pos + inputLen)); pos += inputLen
    const output = String.fromCharCode(...bytes.slice(pos, pos + outputLen)); pos += outputLen
    rules.push({ op, imx, imy, imz, omx, omy, omz, probability, symmetry, input, output })
  }
  assert.equal(pos, bytes.length)
  return { version, values, nodes, rules }
}

assert.equal(xmlAttr('<one values="BW" origin="True" in="WB" out="WW"/>', 'in'), 'WB')
assert.equal(xmlAttr('<one values="BW" origin="True" in="WB" out="WW"/>', 'origin'), 'True')
assert.equal(xmlAttr('<one values="BW"/>', 'missing', 'fallback'), 'fallback')
assert.equal(xmlBoolAttr('<one origin="True"/>', 'origin'), true)
assert.equal(xmlBoolAttr('<one origin="false"/>', 'origin', true), false)
assert.equal(xmlRootStartTag('<!-- comment -->\n<one values="BW"/>'), '<one values="BW"/>')
assert.equal(xmlRootTag('<!-- comment -->\n<one values="BW"/>'), 'one')

assert.deepEqual(parsePattern('WB'), { width: 2, height: 1, depth: 1, data: [...'WB'].map((c) => c.charCodeAt(0)) })
assert.deepEqual(parsePattern('*BB/WBB/*BB'), {
  width: 3,
  height: 3,
  depth: 1,
  data: [...'*BBWBB*BB'].map((c) => c.charCodeAt(0)),
})
assert.deepEqual(parsePattern('AB/CD EF/GH'), {
  width: 2,
  height: 2,
  depth: 2,
  data: [...'EFGHABCD'].map((c) => c.charCodeAt(0)),
})
assert.throws(() => parsePattern('A/BC'), /inconsistent row width/)
assert.throws(() => parsePattern('AB C/D'), /inconsistent row count/)

assert.deepEqual(decodeMjirV1(compileXmlToMjir('<one values="B W" origin="True" in="WB" out="WW" symmetry="()"/>')), {
  version: 1,
  values: 'BW',
  nodes: [],
  rules: [{ op: 2, imx: 2, imy: 1, imz: 1, omx: 2, omy: 1, omz: 1, probability: 1, symmetry: '()', input: 'WB', output: 'WW' }],
})
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<all values="BW" origin="True" in="WB" out="*W"/>')), {
  version: 1,
  values: 'BW',
  nodes: [{ kind: 2, steps: 0 }],
  rules: [{ op: 2, imx: 2, imy: 1, imz: 1, omx: 2, omy: 1, omz: 1, probability: 1, symmetry: '', input: 'WB', output: '*W' }],
})
assert.deepEqual(xmlRuleTags('<all><rule in="WB" out="WW"/><rule in="AW" out="AA" symmetry="()"/></all>').length, 2)
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<all values="BWAD" origin="True" symmetry="(x)"><rule in="WB" out="WW"/><rule in="AW" out="AA" symmetry="()"/></all>')), {
  version: 1,
  values: 'BWAD',
  nodes: [{ kind: 2, steps: 0 }],
  rules: [
    { op: 2, imx: 2, imy: 1, imz: 1, omx: 2, omy: 1, omz: 1, probability: 1, symmetry: '(x)', input: 'WB', output: 'WW' },
    { op: 2, imx: 2, imy: 1, imz: 1, omx: 2, omy: 1, omz: 1, probability: 1, symmetry: '()', input: 'AW', output: 'AA' },
  ],
})
assert.deepEqual(decodeMjirV1(encodeMjirV1({
  values: 'BWA',
  rules: [{ op: 'pattern', input: 'WBB', output: 'WAW', symmetry: '' }],
})).rules[0], { op: 2, imx: 3, imy: 1, imz: 1, omx: 3, omy: 1, omz: 1, probability: 1, symmetry: '', input: 'WBB', output: 'WAW' })
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<prl values="BGR"><rule in="B" out="G" p="0.01"/></prl>')), {
  version: 1,
  values: 'BGR',
  nodes: [{ kind: 3, steps: 0 }],
  rules: [{ op: 2, imx: 1, imy: 1, imz: 1, omx: 1, omy: 1, omz: 1, probability: 0.01, symmetry: '', input: 'B', output: 'G' }],
})
assert.deepEqual(xmlUnionTags('<sequence><union symbol="?" values="BR"/></sequence>').length, 1)
assert.deepEqual(xmlDirectChildTags('<sequence><sequence><one in="B" out="W"/></sequence></sequence>').map(xmlRootTag), ['sequence'])
assert.deepEqual(xmlDirectChildTags('<markov><markov><one in="B" out="W"/></markov><markov><one in="W" out="B"/></markov></markov>').map(xmlRootTag), ['markov', 'markov'])
assert.deepEqual(xmlChildNodeTags('<markov values="BRWU"><one in="RB" out="WR"/><one in="RW" out="UR"/></markov>').length, 2)
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<markov values="BRWU" origin="True"><one in="RB" out="WR"/><one in="RW" out="UR"/></markov>')).nodes, [{ kind: 4, steps: 0 }, { kind: 1, steps: 0 }, { kind: 1, steps: 0 }])
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<sequence values="BR"><one in="B" out="R" steps="24"/><all in="RB" out="BR"/></sequence>')).nodes, [{ kind: 5, steps: 0 }, { kind: 1, steps: 24 }, { kind: 2, steps: 0 }])
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<sequence values="BRACDG"><union symbol="?" values="BR"/><one in="?" out="A"/></sequence>')).rules[0], { op: 101, symbol: '?', values: 'BR' })
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<sequence values="BW"><markov><one in="B" out="W"/></markov></sequence>')).nodes, [{ kind: 5, steps: 0 }, { kind: 4, steps: 0 }, { kind: 1, steps: 0 }])
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<sequence values="BRW"><markov><sequence><one in="B" out="R"/><all in="R" out="W"/></sequence></markov></sequence>')).nodes, [{ kind: 5, steps: 0 }, { kind: 4, steps: 0 }, { kind: 5, steps: 0 }, { kind: 1, steps: 0 }, { kind: 2, steps: 0 }])
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<sequence values="BRW"><markov><markov><one in="B" out="R"/></markov><markov><one in="R" out="W"/></markov></markov></sequence>')).nodes, [{ kind: 5, steps: 0 }, { kind: 4, steps: 0 }, { kind: 4, steps: 0 }, { kind: 1, steps: 0 }, { kind: 4, steps: 0 }, { kind: 1, steps: 0 }])
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<one values="BRW" in="RBB" out="WWR" temperature="0.1"><field for="W" to="R" on="B" recompute="False"/></one>')).rules.slice(0, 2), [
  { op: 104, temperature: 0.1 },
  { op: 103, for: 'W', recompute: false, essential: false, to: 'R', from: '', on: 'B' },
])
assert.throws(() => compileXmlToMjir('<one values="BW" in="B" out="W"><field for="W"/></one>'), /child <field> missing on attribute/)
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<sequence values="BW"><one in="B" out="W"><field for="W" to="B" on="B"/></one></sequence>')).rules[0], { op: 103, for: 'W', recompute: false, essential: false, to: 'B', from: '', on: 'B' })
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<markov values="BRGW"><one search="True" limit="100" depthCoefficient="-1" in="RB" out="WR"><observe value="G" from="B" to="R"/><observe value="B" to="BW"/></one></markov>')).rules.slice(0, 3), [
  { op: 111, enabled: true, limit: 100, depthCoefficient: -1 },
  { op: 105, value: 'G', from: 'B', to: 'R' },
  { op: 105, value: 'B', from: '', to: 'BW' },
])
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<one values="ABCD" file="Rule" legend="ABCD"/>', { loadRulePattern: () => ({ width: 4, height: 1, depth: 1, data: [...'ABCD'] }) })).rules[0], { op: 2, imx: 2, imy: 1, imz: 1, omx: 2, omy: 1, omz: 1, probability: 1, symmetry: '', input: 'AB', output: 'CD' })
assert.throws(() => compileXmlToMjir('<one values="BW" file="Rule"/>'), /file rule missing legend attribute/)
assert.throws(() => compileXmlToMjir('<sequence values="BW"><union values="B"/><one in="B" out="W"/></sequence>'), /union missing symbol attribute/)
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<markov values="BRWD"><path from="R" to="W" on="B" color="D" inertia="True"/></markov>')).rules[0], { op: 106, from: 'R', to: 'W', on: 'B', color: 'D', inertia: true, longest: false, edges: false, vertices: false })
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<sequence values="DA"><convolution neighborhood="Moore" periodic="True"><rule in="D" out="A" sum="3" values="A"/></convolution></sequence>')).rules[0], { op: 107, neighborhood: 'Moore', periodic: true, rules: [{ input: 'D', output: 'A', probability: 1, values: 'A', sum: '3' }] })
const whitePng = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC', 'base64')
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<sequence values="BDA"><convchain sample="Tiny" on="B" black="D" white="A" n="1" steps="2"/></sequence>', { loadSamplePng: () => whitePng })).nodes, [{ kind: 5, steps: 0 }, { kind: 8, steps: 2 }])
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<sequence values="BDA"><convchain sample="Tiny" on="B" black="D" white="A" n="1"/></sequence>', { loadSamplePng: () => whitePng })).rules[0], { op: 108, n: 1, temperature: 1, black: 'D', white: 'A', on: 'B', weights: [0.1, 8] })
assert.throws(() => compileXmlToMjir('<sequence values="BDA"><convchain sample="Tiny" on="B" black="D" white="A"/></sequence>'), /pass loadSamplePng/)
const tinyWfc = decodeMjirV1(compileXmlToMjir('<sequence values="B"><wfc sample="Tiny" values="W" n="1" shannon="True"><rule in="B" out="W"/></wfc></sequence>', { loadSamplePng: () => whitePng }))
assert.deepEqual(tinyWfc.nodes, [{ kind: 5, steps: 0 }, { kind: 9, steps: 0 }])
assert.deepEqual(tinyWfc.rules[0].op, 109)
assert.deepEqual(tinyWfc.rules[0].values, 'W')
assert.deepEqual(tinyWfc.rules[0].patterns, [[0]])
assert.deepEqual(tinyWfc.rules[0].maps, [{ input: 'B', positions: [true] }, { input: 'W', positions: [true] }])
const tinyMap = decodeMjirV1(compileXmlToMjir('<sequence values="BW"><map scale="2 2 1" values="DA"><rule in="W" out="DA/AD"/></map></sequence>'))
assert.deepEqual(tinyMap.nodes, [{ kind: 5, steps: 0 }, { kind: 10, steps: 0 }])
assert.deepEqual(tinyMap.rules[0], { op: 110, sx: { n: 2, d: 1 }, sy: { n: 2, d: 1 }, sz: { n: 1, d: 1 }, values: 'DA', unions: [], rules: [{ imx: 1, imy: 1, imz: 1, omx: 2, omy: 2, omz: 1, probability: 1, symmetry: '', input: 'W', output: 'DAAD' }] })
const tinyMapFout = decodeMjirV1(compileXmlToMjir('<sequence values="BW"><map scale="2 2 1" values="DA"><rule in="W" fout="Out" legend="DA"/></map></sequence>', { loadRulePattern: () => ({ width: 2, height: 1, depth: 1, data: [...'DA'] }) }))
assert.equal(tinyMapFout.rules[0].rules[0].output, 'DA')
const nestedMapFoutFolders = []
const nestedMapFout = decodeMjirV1(compileXmlToMjir('<sequence values="BW"><map scale="1 1 1" values="DA"><sequence><map scale="1 1 1" values="EF" folder="Nested"><rule in="D" fout="Out" legend="EF"/></map></sequence></map></sequence>', { loadRulePattern: (_file, _legend, folder) => { nestedMapFoutFolders.push(folder); return { width: 2, height: 1, depth: 1, data: [...'EF'] } } }))
assert.deepEqual(nestedMapFoutFolders, ['Nested'])
assert.deepEqual(nestedMapFout.rules.filter((rule) => rule.op === 110).map((rule) => rule.op), [110, 110])
assert.deepEqual(decodeMjirV1(compileXmlToMjir('<sequence values="BW"><map scale="2 2 1" values="DA"><rule in="W" out="DA/AD"/><sequence><all in="D" out="A"/></sequence></map></sequence>')).nodes, [{ kind: 5, steps: 0 }, { kind: 10, steps: 0 }, { kind: 5, steps: 0 }, { kind: 2, steps: 0 }])
assert.throws(() => compileXmlToMjir('<map values="BW" in="B" out="W"/>'), /map missing scale attribute/)
assert.equal(decodeMjirV1(compileXmlToMjir('<map scale="1 1 1" values="BW" outputValues="B" transparent="W"><rule in="B" out="W"/></map>')).rules[0].op, 110)
assert.throws(() => compileXmlToMjir('<one values="BW" out="W"/>'), /missing in attribute/)
assert.throws(() => compileXmlToMjir('<all values="BW"><rule out="W"/></all>'), /child <rule> missing in attribute/)

assert.deepEqual(initialGrid(2, 2, 1, 7), [7, 7, 7, 7])
assert.deepEqual(initialGridFromXml('<one values="BW"/>', 3, 3, 1), [0, 0, 0, 0, 0, 0, 0, 0, 0])
assert.deepEqual(initialGridFromXml('<one values="BW" origin="True"/>', 3, 3, 1), [0, 0, 0, 0, 1, 0, 0, 0, 0])
assert.deepEqual(initialGridFromXml('<one values="BW" origin="True"/>', 3, 3, 3).filter((cell) => cell === 1).length, 1)

assert.deepEqual(parseMjstate('MJSTATE 1\nsize 2 2 1\nlegend BW\nBW\nWB\n'), {
  width: 2,
  height: 2,
  depth: 1,
  values: 'BW',
  cells: [0, 1, 1, 0],
})
assert.deepEqual(parseMjstate('MJSTATE 1\nsize 2 1 2\nlegend BW\nz 0\nBW\nz 1\nWB\n'), {
  width: 2,
  height: 1,
  depth: 2,
  values: 'BW',
  cells: [0, 1, 1, 0],
})
assert.throws(() => parseMjstate('nope\n'), /not an MJSTATE 1 file/)

console.log('markov-junior compiler tests ok')
