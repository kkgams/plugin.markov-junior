import { inflateSync } from "node:zlib"
import {
    compileMjirV1FromXml as compileMjirV1FromXmlShared,
    compileXmlToMjir as compileXmlToMjirShared,
} from "../../../packages/util/markov-junior/xml-to-mjir.js"

export * from "../../../packages/util/markov-junior/xml-to-mjir.js"

function withNodeInflate(options = {}) {
    return { inflate: inflateSync, ...options }
}

export function compileXmlToMjir(xml, options = {}) {
    return compileXmlToMjirShared(xml, withNodeInflate(options))
}

export function compileMjirV1FromXml(xml, options = {}) {
    return compileMjirV1FromXmlShared(xml, withNodeInflate(options))
}
