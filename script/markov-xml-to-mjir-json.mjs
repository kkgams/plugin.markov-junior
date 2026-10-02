#!/usr/bin/env node
import { readFileSync, renameSync, writeFileSync } from "node:fs"
import { compileXmlToMjir } from "../plugins/markov-junior.comp/compiler/xml-to-mjir.mjs"

function usage() {
    return `usage: node script/markov-xml-to-mjir-json.mjs input.xml output.mjir.json

Compiles a resource-free MarkovJunior XML model into the JSON byte-array form
used by Lua/nodegraph presets. Resource-backed XML models must still be prepared
by a model-specific compiler wrapper that supplies PNG/VOX/tileset resources.`
}

const [, , inputPath, outputPath] = process.argv
if (!inputPath || !outputPath || process.argv.length !== 4) {
    console.error(usage())
    process.exit(2)
}

const xml = readFileSync(inputPath, "utf8")
const bytes = Array.from(compileXmlToMjir(xml))
const tmpPath = `${outputPath}.tmp-${process.pid}`
writeFileSync(tmpPath, `${JSON.stringify(bytes)}\n`)
renameSync(tmpPath, outputPath)

console.log(`${inputPath} -> ${outputPath} (${bytes.length} bytes)`)
