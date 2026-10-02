const textEncoder = new TextEncoder()

function u32le(out, value) {
    out.push(value & 0xff, (value >>> 8) & 0xff, (value >>> 16) & 0xff, (value >>> 24) & 0xff)
}

function f64le(out, value) {
    const buffer = new ArrayBuffer(8)
    new DataView(buffer).setFloat64(0, value, true)
    out.push(...new Uint8Array(buffer))
}

export function xmlAttr(xml, name, fallback = "") {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    const match = xml.match(new RegExp(`(?:^|[\\s<])${escaped}\\s*=\\s*"([^"]*)"`))
    return match?.[1] ?? fallback
}

export function xmlRootStartTag(xml) {
    const withoutComments = xml.replace(/<!--([\s\S]*?)-->/g, "").trimStart()
    return withoutComments.match(/^<[^>]+>/)?.[0] ?? ""
}

export function xmlRootTag(xml) {
    return xmlRootStartTag(xml).match(/^<([a-zA-Z0-9_-]+)/)?.[1] ?? ""
}

export function xmlBoolAttr(xml, name, fallback = false) {
    const value = xmlAttr(xml, name, "")
    if (value === "") return fallback
    return value === "True" || value === "true"
}

export function parsePattern(pattern) {
    const layers = pattern.split(" ")
    const rows0 = layers[0].split("/")
    const width = rows0[0].length
    const height = rows0.length
    const depth = layers.length
    const data = []

    for (let z = 0; z < depth; z++) {
        const layer = layers[depth - 1 - z]
        const rows = layer.split("/")
        if (rows.length !== height) throw new Error(`pattern has inconsistent row count: ${pattern}`)
        for (let y = 0; y < height; y++) {
            if (rows[y].length !== width) throw new Error(`pattern has inconsistent row width: ${pattern}`)
            for (let x = 0; x < width; x++) data.push(rows[y].charCodeAt(x))
        }
    }
    return { width, height, depth, data }
}

function paethPredictor(a, b, c) {
    const p = a + b - c
    const pa = Math.abs(p - a)
    const pb = Math.abs(p - b)
    const pc = Math.abs(p - c)
    if (pa <= pb && pa <= pc) return a
    if (pb <= pc) return b
    return c
}

function decodePngRgba(bytes, options = {}) {
    if (bytes && typeof bytes === "object" && !ArrayBuffer.isView(bytes) && !Array.isArray(bytes)) {
        if (!Number.isInteger(bytes.width) || !Number.isInteger(bytes.height) || !Array.isArray(bytes.colors))
            throw new Error("decoded PNG sample must have width, height, and colors")
        return { width: bytes.width, height: bytes.height, colors: bytes.colors }
    }
    if (bytes[0] !== 0x89 || bytes[1] !== 0x50 || bytes[2] !== 0x4e || bytes[3] !== 0x47)
        throw new Error("sample is not a PNG")
    let pos = 8
    let width = 0
    let height = 0
    let bitDepth = 0
    let colorType = 0
    let palette = []
    let transparency = []
    const idat = []
    while (pos + 8 <= bytes.length) {
        const len = (bytes[pos] << 24) | (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3]
        const type = String.fromCharCode(...bytes.slice(pos + 4, pos + 8))
        const dataStart = pos + 8
        const dataEnd = dataStart + len
        if (type === "IHDR") {
            width =
                (bytes[dataStart] << 24) |
                (bytes[dataStart + 1] << 16) |
                (bytes[dataStart + 2] << 8) |
                bytes[dataStart + 3]
            height =
                (bytes[dataStart + 4] << 24) |
                (bytes[dataStart + 5] << 16) |
                (bytes[dataStart + 6] << 8) |
                bytes[dataStart + 7]
            bitDepth = bytes[dataStart + 8]
            colorType = bytes[dataStart + 9]
            const interlace = bytes[dataStart + 12]
            if (interlace !== 0) throw new Error("interlaced PNG samples are unsupported")
        } else if (type === "PLTE") {
            palette = []
            for (let i = 0; i + 2 < len; i += 3)
                palette.push([bytes[dataStart + i], bytes[dataStart + i + 1], bytes[dataStart + i + 2]])
        } else if (type === "tRNS") {
            transparency = [...bytes.slice(dataStart, dataEnd)]
        } else if (type === "IDAT") {
            idat.push(...bytes.slice(dataStart, dataEnd))
        } else if (type === "IEND") break
        pos = dataEnd + 4
    }
    if (colorType === 3) {
        if (![1, 2, 4, 8].includes(bitDepth)) throw new Error(`unsupported indexed PNG bitDepth=${bitDepth}`)
        if (palette.length === 0) throw new Error("indexed PNG sample missing palette")
    } else if (bitDepth !== 8 || ![0, 2, 4, 6].includes(colorType)) {
        throw new Error(`unsupported PNG sample format bitDepth=${bitDepth} colorType=${colorType}`)
    }
    const channels = colorType === 0 ? 1 : colorType === 2 ? 3 : colorType === 3 ? 1 : colorType === 4 ? 2 : 4
    const bitsPerPixel = colorType === 3 ? bitDepth : channels * bitDepth
    const stride = Math.ceil((width * bitsPerPixel) / 8)
    const filterBpp = Math.max(1, Math.ceil(bitsPerPixel / 8))
    const inflate = options.inflate
    if (typeof inflate !== "function") throw new Error("PNG decoding requires options.inflate")
    const raw = inflate(Uint8Array.from(idat))
    const scanlines = new Uint8Array(height * stride)
    let rp = 0
    for (let y = 0; y < height; y++) {
        const filter = raw[rp++]
        const rowStart = y * stride
        const prevStart = (y - 1) * stride
        for (let x = 0; x < stride; x++) {
            const left = x >= filterBpp ? scanlines[rowStart + x - filterBpp] : 0
            const up = y > 0 ? scanlines[prevStart + x] : 0
            const upLeft = y > 0 && x >= filterBpp ? scanlines[prevStart + x - filterBpp] : 0
            let value = raw[rp++]
            if (filter === 1) value = (value + left) & 0xff
            else if (filter === 2) value = (value + up) & 0xff
            else if (filter === 3) value = (value + Math.floor((left + up) / 2)) & 0xff
            else if (filter === 4) value = (value + paethPredictor(left, up, upLeft)) & 0xff
            else if (filter !== 0) throw new Error(`unsupported PNG filter ${filter}`)
            scanlines[rowStart + x] = value
        }
    }
    const colors = []
    if (colorType === 3) {
        const mask = (1 << bitDepth) - 1
        for (let y = 0; y < height; y++)
            for (let x = 0; x < width; x++) {
                const bitOffset = x * bitDepth
                const packed = scanlines[y * stride + (bitOffset >> 3)]
                const shift = 8 - bitDepth - (bitOffset & 7)
                const index = (packed >> shift) & mask
                const [r, g, b] = palette[index] ?? [0, 0, 0]
                const a = transparency[index] ?? 0xff
                colors.push(((a << 24) >>> 0) | (r << 16) | (g << 8) | b)
            }
    } else {
        const pixels = scanlines
        for (let i = 0; i < width * height; i++) {
            const p = i * channels
            let r,
                g,
                b,
                a = 0xff
            if (colorType === 0) {
                r = g = b = pixels[p]
            } else if (colorType === 2) {
                r = pixels[p]
                g = pixels[p + 1]
                b = pixels[p + 2]
            } else if (colorType === 4) {
                r = g = b = pixels[p]
                a = pixels[p + 1]
            } else {
                r = pixels[p]
                g = pixels[p + 1]
                b = pixels[p + 2]
                a = pixels[p + 3]
            }
            colors.push(((a << 24) >>> 0) | (r << 16) | (g << 8) | b)
        }
    }
    return { width, height, colors }
}

function decodePngPattern(bytes, legend, options = {}) {
    const { width, height, colors } = decodePngRgba(bytes, options)
    const uniques = []
    const data = colors.map((color) => {
        let ord = uniques.indexOf(color)
        if (ord < 0) {
            ord = uniques.length
            uniques.push(color)
        }
        if (ord >= legend.length) throw new Error(`rule PNG uses ${ord + 1} colors but legend has ${legend.length}`)
        return legend[ord]
    })
    return { width, height, depth: 1, data }
}

function leI32(bytes, off) {
    return bytes[off] | (bytes[off + 1] << 8) | (bytes[off + 2] << 16) | (bytes[off + 3] << 24)
}

function decodeVoxInts(bytes) {
    if (String.fromCharCode(...bytes.slice(0, 4)) !== "VOX ") throw new Error("resource is not a VOX file")
    let mx = -1,
        my = -1,
        mz = -1
    let colors = null
    let off = 8
    while (off + 12 <= bytes.length) {
        const id = String.fromCharCode(...bytes.slice(off, off + 4))
        const chunkSize = leI32(bytes, off + 4)
        off += 12
        if (id === "SIZE" && off + 12 <= bytes.length) {
            mx = leI32(bytes, off)
            my = leI32(bytes, off + 4)
            mz = leI32(bytes, off + 8)
        } else if (id === "XYZI" && mx > 0 && my > 0 && mz > 0 && off + 4 <= bytes.length) {
            colors = Array(mx * my * mz).fill(-1)
            const n = leI32(bytes, off)
            let pos = off + 4
            for (let i = 0; i < n; i++) {
                const x = bytes[pos],
                    y = bytes[pos + 1],
                    z = bytes[pos + 2],
                    c = bytes[pos + 3]
                pos += 4
                colors[x + y * mx + z * mx * my] = c
            }
        }
        off += chunkSize
    }
    if (!colors) throw new Error("VOX resource missing SIZE/XYZI chunks")
    return { width: mx, height: my, depth: mz, colors }
}

function decodeVoxPattern(bytes, legend) {
    const { width: mx, height: my, depth: mz, colors } = decodeVoxInts(bytes)
    const uniques = []
    const data = colors.map((color) => {
        let ord = uniques.indexOf(color)
        if (ord < 0) {
            ord = uniques.length
            uniques.push(color)
        }
        if (ord >= legend.length) throw new Error(`rule VOX uses ${ord + 1} colors but legend has ${legend.length}`)
        return legend[ord]
    })
    return { width: mx, height: my, depth: mz, data }
}

function decodePngWhiteMask(bytes, options = {}) {
    const { width, height, colors } = decodePngRgba(bytes, options)
    return {
        width,
        height,
        sample: colors.map(
            (color) => ((color >>> 16) & 0xff) === 255 && ((color >>> 8) & 0xff) === 255 && (color & 0xff) === 255,
        ),
    }
}

function convchainPatternIndex(pattern) {
    let index = 0
    for (let i = 0; i < pattern.length; i++) if (pattern[i]) index += 1 << i
    return index
}

function convchainRotated(pattern, n) {
    const out = Array(n * n).fill(false)
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) out[x + y * n] = pattern[n - 1 - y + x * n]
    return out
}

function convchainReflected(pattern, n) {
    const out = Array(n * n).fill(false)
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) out[x + y * n] = pattern[n - 1 - x + y * n]
    return out
}

function squareSymmetryEnabled(symmetry, i) {
    if (symmetry === "" || symmetry === "(xy)") return true
    if (symmetry === "()") return i === 0
    if (symmetry === "(x)") return i === 0 || i === 1
    if (symmetry === "(y)") return i === 0 || i === 5
    if (symmetry === "(x)(y)") return i === 0 || i === 1 || i === 4 || i === 5
    if (symmetry === "(xy+)") return i === 0 || i === 2 || i === 4 || i === 6
    return true
}

function convchainWeightsFromSample(samplePngBytes, n, symmetry, options = {}) {
    const { width, height, sample } = decodePngWhiteMask(samplePngBytes, options)
    const weights = Array(1 << (n * n)).fill(0)
    for (let y = 0; y < height; y++)
        for (let x = 0; x < width; x++) {
            const base = []
            for (let dy = 0; dy < n; dy++)
                for (let dx = 0; dx < n; dx++) base.push(sample[((x + dx) % width) + ((y + dy) % height) * width])
            const patterns = []
            patterns[0] = base
            patterns[1] = convchainReflected(patterns[0], n)
            patterns[2] = convchainRotated(patterns[0], n)
            patterns[3] = convchainReflected(patterns[2], n)
            patterns[4] = convchainRotated(patterns[2], n)
            patterns[5] = convchainReflected(patterns[4], n)
            patterns[6] = convchainRotated(patterns[4], n)
            patterns[7] = convchainReflected(patterns[6], n)
            for (let i = 0; i < 8; i++)
                if (squareSymmetryEnabled(symmetry, i)) weights[convchainPatternIndex(patterns[i])] += 1
        }
    for (let i = 0; i < weights.length; i++) if (weights[i] <= 0) weights[i] = 0.1
    return weights
}

function overlapPatternIndex(pattern, colorCount) {
    let result = 0
    let power = 1
    for (let i = 0; i < pattern.length; i++) {
        result += pattern[pattern.length - 1 - i] * power
        power *= colorCount
    }
    return result
}

function overlapPatternFromIndex(index, colorCount, n) {
    let residue = index
    let power = 1
    for (let i = 0; i < n * n; i++) power *= colorCount
    const result = []
    for (let i = 0; i < n * n; i++) {
        power = Math.floor(power / colorCount)
        let count = 0
        while (residue >= power) {
            residue -= power
            count++
        }
        result.push(count)
    }
    return result
}

function overlapAgrees(p1, p2, dx, dy, n) {
    let xmin = 0,
        xmax = n,
        ymin = 0,
        ymax = n
    if (dx < 0) xmax = dx + n
    else xmin = dx
    if (dy < 0) ymax = dy + n
    else ymin = dy
    for (let y = ymin; y < ymax; y++)
        for (let x = xmin; x < xmax; x++) if (p1[x + n * y] !== p2[x - dx + n * (y - dy)]) return false
    return true
}

function parseScalePair(s) {
    if (s.includes("/")) {
        const [n, d] = s.split("/").map(Number)
        return { n, d }
    }
    return { n: Number(s), d: 1 }
}

function mapFromElement(elementXml, inheritedSymmetry, options) {
    const start = xmlRootStartTag(elementXml)
    const scale = xmlAttr(start, "scale")
    const values = xmlAttr(start, "values")
    if (!scale) throw new Error("map missing scale attribute")
    if (!values) throw new Error("map missing values attribute")
    const scaleParts = scale.trim().split(/\s+/)
    if (scaleParts.length !== 3) throw new Error("map scale must have 3 parts")
    const [sx, sy, sz] = scaleParts.map(parseScalePair)
    const direct = xmlDirectChildTags(elementXml)
    const unsupported = direct
        .map((childXml) => xmlRootTag(childXml))
        .filter(
            (childTag) =>
                ![
                    "rule",
                    "union",
                    "one",
                    "all",
                    "prl",
                    "path",
                    "convolution",
                    "convchain",
                    "wfc",
                    "map",
                    "markov",
                    "sequence",
                ].includes(childTag),
        )
    if (unsupported.length > 0) throw new Error(`map has unsupported direct children: ${unsupported.join(", ")}`)
    const symmetry = xmlAttr(start, "symmetry", inheritedSymmetry)
    const mapOptions = { ...options, folder: xmlAttr(start, "folder", options.folder ?? "") }
    const ruleTags = direct.filter((childXml) => xmlRootTag(childXml) === "rule")
    const rules = []
    for (const ruleTag of ruleTags) {
        const file = xmlAttr(ruleTag, "file")
        const fin = xmlAttr(ruleTag, "fin")
        const fout = xmlAttr(ruleTag, "fout")
        const ruleSymmetry = xmlAttr(ruleTag, "symmetry", symmetry)
        const probability = Number(xmlAttr(ruleTag, "p", "1"))
        if (file) {
            const legend = xmlAttr(ruleTag, "legend")
            if (!legend) throw new Error("map <rule file> missing legend attribute")
            const split = splitFileRulePattern(loadRuleResourcePattern(file, legend, mapOptions))
            rules.push({
                input: encodePatternLiteral(split.input, split.inputShape),
                output: encodePatternLiteral(split.output, split.outputShape),
                symmetry: ruleSymmetry,
                probability,
            })
            continue
        }
        const legend = xmlAttr(ruleTag, "legend")
        const input = xmlAttr(ruleTag, "in")
        const output = xmlAttr(ruleTag, "out")
        let encodedInput = input
        let encodedOutput = output
        if (fin) {
            if (!legend) throw new Error("map <rule fin> missing legend attribute")
            const p = loadRuleResourcePattern(fin, legend, mapOptions)
            encodedInput = encodePatternLiteral(p.data.join(""), { width: p.width, height: p.height, depth: p.depth })
        }
        if (fout) {
            if (!legend) throw new Error("map <rule fout> missing legend attribute")
            const p = loadRuleResourcePattern(fout, legend, mapOptions)
            encodedOutput = encodePatternLiteral(p.data.join(""), { width: p.width, height: p.height, depth: p.depth })
        }
        if (!encodedInput) throw new Error("map <rule> missing in/fin attribute")
        if (!encodedOutput) throw new Error("map <rule> missing out/fout attribute")
        rules.push({ input: encodedInput, output: encodedOutput, symmetry: ruleSymmetry, probability })
    }
    const children = direct
        .filter((childXml) => !["rule", "union"].includes(xmlRootTag(childXml)))
        .map((childXml) => nodeFromElement(childXml, symmetry, { ...mapOptions, values }))
    if (rules.length === 0 && children.length === 0) throw new Error("map missing child <rule> elements or child nodes")
    return { values, sx, sy, sz, rules, unions: unionsFromXml(elementXml), children }
}

function tileZRotate(p, s, sz) {
    const q = Array(p.length)
    for (let z = 0; z < sz; z++)
        for (let y = 0; y < s; y++)
            for (let x = 0; x < s; x++) q[x + y * s + z * s * s] = p[y + (s - 1 - x) * s + z * s * s]
    return q
}
function tileYRotate(p, s, sz) {
    const q = Array(p.length)
    for (let z = 0; z < sz; z++)
        for (let y = 0; y < s; y++)
            for (let x = 0; x < s; x++) q[x + y * s + z * s * s] = p[z + y * s + (s - 1 - x) * s * s]
    return q
}
function tileXRotate(p, s, sz) {
    const q = Array(p.length)
    for (let z = 0; z < s; z++)
        for (let y = 0; y < sz; y++)
            for (let x = 0; x < s; x++) q[x + y * s + z * s * sz] = p[x + z * s + (s - 1 - y) * s * s]
    return q
}
function tileXReflect(p, s, sz) {
    const q = Array(p.length)
    for (let z = 0; z < sz; z++)
        for (let y = 0; y < s; y++)
            for (let x = 0; x < s; x++) q[x + y * s + z * s * s] = p[s - 1 - x + y * s + z * s * s]
    return q
}
function tileYReflect(p, s, sz) {
    const q = Array(p.length)
    for (let z = 0; z < sz; z++)
        for (let y = 0; y < s; y++)
            for (let x = 0; x < s; x++) q[x + y * s + z * s * s] = p[x + (s - 1 - y) * s + z * s * s]
    return q
}
function tileZReflect(p, s, sz) {
    const q = Array(p.length)
    for (let z = 0; z < sz; z++)
        for (let y = 0; y < s; y++)
            for (let x = 0; x < s; x++) q[x + y * s + z * s * s] = p[x + y * s + (sz - 1 - z) * s * s]
    return q
}
function tileSame(a, b) {
    return a.length === b.length && a.every((v, i) => v === b[i])
}
function tileIndex(list, p) {
    return list.findIndex((q) => tileSame(q, p))
}
function tileSquareSymmetriesRf(base, s, sz, rot, refl) {
    const arr = []
    arr[0] = [...base]
    arr[1] = refl(arr[0], s, sz)
    arr[2] = rot(arr[0], s, sz)
    arr[3] = refl(arr[2], s, sz)
    arr[4] = rot(arr[2], s, sz)
    arr[5] = refl(arr[4], s, sz)
    arr[6] = rot(arr[4], s, sz)
    arr[7] = refl(arr[6], s, sz)
    return arr
}
function tileSquareSymmetriesNoUnique(base, s, sz) {
    return tileSquareSymmetriesRf(base, s, sz, tileZRotate, tileXReflect)
}
function tileSquareSymmetries(base, s, sz) {
    const out = []
    for (const p of tileSquareSymmetriesNoUnique(base, s, sz)) if (!out.some((q) => tileSame(q, p))) out.push(p)
    return out
}
function tileCubeSymmetries(base, s, sz) {
    const arr = []
    arr[0] = [...base]
    arr[1] = tileXReflect(arr[0], s, sz)
    arr[2] = tileZRotate(arr[0], s, sz)
    arr[3] = tileXReflect(arr[2], s, sz)
    arr[4] = tileZRotate(arr[2], s, sz)
    arr[5] = tileXReflect(arr[4], s, sz)
    arr[6] = tileZRotate(arr[4], s, sz)
    arr[7] = tileXReflect(arr[6], s, sz)
    arr[8] = tileYRotate(arr[0], s, sz)
    arr[9] = tileXReflect(arr[8], s, sz)
    arr[10] = tileYRotate(arr[2], s, sz)
    arr[11] = tileXReflect(arr[10], s, sz)
    arr[12] = tileYRotate(arr[4], s, sz)
    arr[13] = tileXReflect(arr[12], s, sz)
    arr[14] = tileYRotate(arr[6], s, sz)
    arr[15] = tileXReflect(arr[14], s, sz)
    arr[16] = tileYRotate(arr[8], s, sz)
    arr[17] = tileXReflect(arr[16], s, sz)
    arr[18] = tileYRotate(arr[10], s, sz)
    arr[19] = tileXReflect(arr[18], s, sz)
    arr[20] = tileYRotate(arr[12], s, sz)
    arr[21] = tileXReflect(arr[20], s, sz)
    arr[22] = tileYRotate(arr[14], s, sz)
    arr[23] = tileXReflect(arr[22], s, sz)
    arr[24] = tileYRotate(arr[16], s, sz)
    arr[25] = tileXReflect(arr[24], s, sz)
    arr[26] = tileYRotate(arr[18], s, sz)
    arr[27] = tileXReflect(arr[26], s, sz)
    arr[28] = tileYRotate(arr[20], s, sz)
    arr[29] = tileXReflect(arr[28], s, sz)
    arr[30] = tileYRotate(arr[22], s, sz)
    arr[31] = tileXReflect(arr[30], s, sz)
    arr[32] = tileZRotate(arr[8], s, sz)
    arr[33] = tileXReflect(arr[32], s, sz)
    arr[34] = tileZRotate(arr[10], s, sz)
    arr[35] = tileXReflect(arr[34], s, sz)
    arr[36] = tileZRotate(arr[12], s, sz)
    arr[37] = tileXReflect(arr[36], s, sz)
    arr[38] = tileZRotate(arr[14], s, sz)
    arr[39] = tileXReflect(arr[38], s, sz)
    arr[40] = tileZRotate(arr[24], s, sz)
    arr[41] = tileXReflect(arr[40], s, sz)
    arr[42] = tileZRotate(arr[26], s, sz)
    arr[43] = tileXReflect(arr[42], s, sz)
    arr[44] = tileZRotate(arr[28], s, sz)
    arr[45] = tileXReflect(arr[44], s, sz)
    arr[46] = tileZRotate(arr[30], s, sz)
    arr[47] = tileXReflect(arr[46], s, sz)
    const out = []
    for (const p of arr) if (!out.some((q) => tileSame(q, p))) out.push(p)
    return out
}
function tileFromAttr(attr, named, patterns, s, sz) {
    const parts = attr.split(" ")
    const action = parts.length === 2 ? parts[0] : ""
    const name = parts.length === 2 ? parts[1] : attr
    const found = named.find((nt) => nt.name === name)
    let p = [...patterns[found?.start ?? 0]]
    for (let i = action.length - 1; i >= 0; i--) {
        if (action[i] === "z") p = tileZRotate(p, s, sz)
        else if (action[i] === "y") p = tileYRotate(p, s, sz)
        else if (action[i] === "x") p = tileXRotate(p, s, sz)
    }
    return p
}

function tileWfcFromElement(elementXml, inheritedSymmetry, options) {
    const start = xmlRootStartTag(elementXml)
    const name = xmlAttr(start, "tileset")
    const tilesName = xmlAttr(start, "tiles", name)
    const values = xmlAttr(start, "values")
    if (!name) throw new Error("tile wfc missing tileset attribute")
    if (!values) throw new Error("tile wfc missing values attribute")
    const tilesetXml = options?.loadTilesetXml?.(name)
    if (!tilesetXml) throw new Error(`tileset ${name} unavailable; pass loadTilesetXml option`)
    const tilesParent = tilesetXml.match(/<tiles\b[^>]*>[\s\S]*?<\/tiles>/)?.[0] ?? ""
    const neighborsParent = tilesetXml.match(/<neighbors\b[^>]*>[\s\S]*?<\/neighbors>/)?.[0] ?? ""
    const tileTags = xmlDirectChildTags(tilesParent).filter((tag) => xmlRootTag(tag) === "tile")
    if (tileTags.length === 0) throw new Error(`tileset ${name} has no tiles`)
    const full = xmlBoolAttr(xmlRootStartTag(tilesetXml), "fullSymmetry", false)
    const firstName = xmlAttr(xmlRootStartTag(tileTags[0]), "name")
    const firstVox = options?.loadTileVox?.(tilesName, firstName)
    if (!firstVox) throw new Error(`tile ${tilesName}/${firstName} unavailable; pass loadTileVox option`)
    const first = decodeVoxInts(firstVox)
    if (first.width <= 0 || first.width !== first.height) throw new Error("tile WFC requires square tiles")
    if (full && first.width !== first.depth) throw new Error("full-symmetry tile WFC requires cubic tiles")
    const tileS = first.width,
        tileSz = first.depth
    const uniques = []
    const patterns = [],
        weights = [],
        named = []
    const ords = (colors) =>
        colors.map((color) => {
            let ord = uniques.indexOf(color)
            if (ord < 0) {
                ord = uniques.length
                uniques.push(color)
            }
            return ord
        })
    for (const tileTag of tileTags) {
        const tname = xmlAttr(xmlRootStartTag(tileTag), "name")
        const vox = options?.loadTileVox?.(tilesName, tname)
        if (!vox) throw new Error(`tile ${tilesName}/${tname} unavailable; pass loadTileVox option`)
        const decoded = decodeVoxInts(vox)
        if (decoded.width !== tileS || decoded.height !== tileS || decoded.depth !== tileSz)
            throw new Error(`tile ${tilesName}/${tname} dimensions differ`)
        const startIndex = patterns.length
        const locals = full
            ? tileCubeSymmetries(ords(decoded.colors), tileS, tileSz)
            : tileSquareSymmetries(ords(decoded.colors), tileS, tileSz)
        for (const p of locals) {
            patterns.push(p)
            weights.push(Number(xmlAttr(xmlRootStartTag(tileTag), "weight", "1")))
        }
        named.push({ name: tname, start: startIndex, count: locals.length })
    }
    const p = patterns.length
    if (p === 0) throw new Error("tile WFC has no patterns")
    const temp = Array(6 * p * p).fill(false)
    const setprop = (d, a, b) => {
        if (a >= 0 && b >= 0) temp[(d * p + a) * p + b] = true
    }
    for (const neighborXml of xmlDirectChildTags(neighborsParent).filter((tag) => xmlRootTag(tag) === "neighbor")) {
        const tag = xmlRootStartTag(neighborXml),
            left = xmlAttr(tag, "left"),
            right = xmlAttr(tag, "right")
        if (left && full) {
            const lt = tileFromAttr(left, named, patterns, tileS, tileSz),
                rt = tileFromAttr(right, named, patterns, tileS, tileSz)
            const lsym = tileSquareSymmetriesRf(lt, tileS, tileSz, tileXRotate, tileYReflect),
                rsym = tileSquareSymmetriesRf(rt, tileS, tileSz, tileXRotate, tileYReflect)
            for (let i = 0; i < lsym.length; i++) {
                setprop(0, tileIndex(patterns, lsym[i]), tileIndex(patterns, rsym[i]))
                setprop(
                    0,
                    tileIndex(patterns, tileXReflect(rsym[i], tileS, tileSz)),
                    tileIndex(patterns, tileXReflect(lsym[i], tileS, tileSz)),
                )
            }
            const dt = tileZRotate(lt, tileS, tileSz),
                ut = tileZRotate(rt, tileS, tileSz)
            const dsym = tileSquareSymmetriesRf(dt, tileS, tileSz, tileYRotate, tileZReflect),
                usym = tileSquareSymmetriesRf(ut, tileS, tileSz, tileYRotate, tileZReflect)
            for (let i = 0; i < dsym.length; i++) {
                setprop(1, tileIndex(patterns, dsym[i]), tileIndex(patterns, usym[i]))
                setprop(
                    1,
                    tileIndex(patterns, tileYReflect(usym[i], tileS, tileSz)),
                    tileIndex(patterns, tileYReflect(dsym[i], tileS, tileSz)),
                )
            }
            const bt = tileYRotate(lt, tileS, tileSz),
                tt = tileYRotate(rt, tileS, tileSz)
            const bsym = tileSquareSymmetriesRf(bt, tileS, tileSz, tileZRotate, tileXReflect),
                tsym = tileSquareSymmetriesRf(tt, tileS, tileSz, tileZRotate, tileXReflect)
            for (let i = 0; i < bsym.length; i++) {
                setprop(4, tileIndex(patterns, bsym[i]), tileIndex(patterns, tsym[i]))
                setprop(
                    4,
                    tileIndex(patterns, tileZReflect(tsym[i], tileS, tileSz)),
                    tileIndex(patterns, tileZReflect(bsym[i], tileS, tileSz)),
                )
            }
        } else if (left) {
            const lt = tileFromAttr(left, named, patterns, tileS, tileSz),
                rt = tileFromAttr(right, named, patterns, tileS, tileSz)
            setprop(0, tileIndex(patterns, lt), tileIndex(patterns, rt))
            setprop(
                0,
                tileIndex(patterns, tileYReflect(lt, tileS, tileSz)),
                tileIndex(patterns, tileYReflect(rt, tileS, tileSz)),
            )
            setprop(
                0,
                tileIndex(patterns, tileXReflect(rt, tileS, tileSz)),
                tileIndex(patterns, tileXReflect(lt, tileS, tileSz)),
            )
            setprop(
                0,
                tileIndex(patterns, tileYReflect(tileXReflect(rt, tileS, tileSz), tileS, tileSz)),
                tileIndex(patterns, tileYReflect(tileXReflect(lt, tileS, tileSz), tileS, tileSz)),
            )
            const dt = tileZRotate(lt, tileS, tileSz),
                ut = tileZRotate(rt, tileS, tileSz)
            setprop(1, tileIndex(patterns, dt), tileIndex(patterns, ut))
            setprop(
                1,
                tileIndex(patterns, tileXReflect(dt, tileS, tileSz)),
                tileIndex(patterns, tileXReflect(ut, tileS, tileSz)),
            )
            setprop(
                1,
                tileIndex(patterns, tileYReflect(ut, tileS, tileSz)),
                tileIndex(patterns, tileYReflect(dt, tileS, tileSz)),
            )
            setprop(
                1,
                tileIndex(patterns, tileXReflect(tileYReflect(ut, tileS, tileSz), tileS, tileSz)),
                tileIndex(patterns, tileXReflect(tileYReflect(dt, tileS, tileSz), tileS, tileSz)),
            )
        } else {
            const tt = tileFromAttr(xmlAttr(tag, "top"), named, patterns, tileS, tileSz),
                bt = tileFromAttr(xmlAttr(tag, "bottom"), named, patterns, tileS, tileSz)
            const tsym = tileSquareSymmetriesNoUnique(tt, tileS, tileSz),
                bsym = tileSquareSymmetriesNoUnique(bt, tileS, tileSz)
            for (let i = 0; i < tsym.length; i++) setprop(4, tileIndex(patterns, bsym[i]), tileIndex(patterns, tsym[i]))
        }
    }
    for (let p2 = 0; p2 < p; p2++)
        for (let p1 = 0; p1 < p; p1++) {
            temp[(2 * p + p2) * p + p1] = temp[(0 * p + p1) * p + p2]
            temp[(3 * p + p2) * p + p1] = temp[(1 * p + p1) * p + p2]
            temp[(5 * p + p2) * p + p1] = temp[(4 * p + p1) * p + p2]
        }
    const propagator = []
    for (let d = 0; d < 6; d++) {
        const dir = []
        for (let p1 = 0; p1 < p; p1++) {
            const list = []
            for (let p2 = 0; p2 < p; p2++) if (temp[(d * p + p1) * p + p2]) list.push(p2)
            dir.push(list)
        }
        propagator.push(dir)
    }
    const maps = xmlDirectChildTags(elementXml)
        .filter((tag) => xmlRootTag(tag) === "rule")
        .map((ruleXml) => {
            const tag = xmlRootStartTag(ruleXml),
                outs = xmlAttr(tag, "out").split("|")
            const positions = Array(p).fill(false)
            for (const out of outs)
                for (const nt of named)
                    if (nt.name === out) for (let i = nt.start; i < nt.start + nt.count; i++) positions[i] = true
            return { input: xmlAttr(tag, "in"), positions }
        })
    if (!maps.some((map) => map.input.charCodeAt(0) === 0)) maps.push({ input: "\0", positions: Array(p).fill(true) })
    return {
        tile: true,
        values,
        periodic: xmlBoolAttr(start, "periodic", false),
        shannon: xmlBoolAttr(start, "shannon", false),
        tries: Number(xmlAttr(start, "tries", "1000")),
        tileS,
        tileSz,
        overlap: Number(xmlAttr(start, "overlap", "0")),
        overlapz: Number(xmlAttr(start, "overlapz", "0")),
        patterns,
        weights,
        propagator,
        maps,
    }
}

function wfcOverlapFromElement(elementXml, inheritedSymmetry, options) {
    const start = xmlRootStartTag(elementXml)
    const sampleName = xmlAttr(start, "sample")
    const values = xmlAttr(start, "values")
    if (!sampleName) throw new Error("wfc overlap missing sample attribute")
    if (!values) throw new Error("wfc overlap missing values attribute")
    const samplePng = options?.loadSamplePng?.(sampleName)
    if (!samplePng) throw new Error(`wfc sample ${sampleName} unavailable; pass loadSamplePng option`)
    const n = Number(xmlAttr(start, "n", "3"))
    const { width, height, colors } = decodePngRgba(samplePng, options)
    const uniques = []
    const sample = colors.map((color) => {
        let idx = uniques.indexOf(color)
        if (idx < 0) {
            idx = uniques.length
            uniques.push(color)
        }
        return idx
    })
    const colorCount = uniques.length
    const keys = []
    const counts = []
    const ordering = []
    const periodicInput = xmlBoolAttr(start, "periodicInput", true)
    const xmax = periodicInput ? width : width - n + 1
    const ymax = periodicInput ? height : height - n + 1
    const symmetry = xmlAttr(start, "symmetry", inheritedSymmetry)
    for (let y = 0; y < ymax; y++)
        for (let x = 0; x < xmax; x++) {
            const base = []
            for (let dy = 0; dy < n; dy++)
                for (let dx = 0; dx < n; dx++) base.push(sample[((x + dx) % width) + ((y + dy) % height) * width])
            const patterns = []
            patterns[0] = base
            patterns[1] = convchainReflected(patterns[0], n)
            patterns[2] = convchainRotated(patterns[0], n)
            patterns[3] = convchainReflected(patterns[2], n)
            patterns[4] = convchainRotated(patterns[2], n)
            patterns[5] = convchainReflected(patterns[4], n)
            patterns[6] = convchainRotated(patterns[4], n)
            patterns[7] = convchainReflected(patterns[6], n)
            for (let i = 0; i < 8; i++)
                if (squareSymmetryEnabled(symmetry, i)) {
                    const index = overlapPatternIndex(patterns[i], colorCount)
                    const found = keys.indexOf(index)
                    if (found >= 0) counts[found] += 1
                    else {
                        keys.push(index)
                        counts.push(1)
                        ordering.push(index)
                    }
                }
        }
    const patterns = ordering.map((index) => overlapPatternFromIndex(index, colorCount, n))
    const weights = ordering.map((index) => counts[keys.indexOf(index)])
    const dirs = [
        [1, 0],
        [0, 1],
        [-1, 0],
        [0, -1],
    ]
    const propagator = dirs.map(([dx, dy]) =>
        patterns.map((p) => patterns.map((p2, i) => (overlapAgrees(p, p2, dx, dy, n) ? i : -1)).filter((i) => i >= 0)),
    )
    const maps = xmlDirectChildTags(elementXml)
        .filter((child) => xmlRootTag(child) === "rule")
        .map((ruleXml) => {
            const tag = xmlRootStartTag(ruleXml)
            const input = xmlAttr(tag, "in")
            const out = xmlAttr(tag, "out")
            if (!input) throw new Error("wfc rule missing in attribute")
            if (!out) throw new Error("wfc rule missing out attribute")
            const outs = out.split("|").map((part) => values.indexOf(part[0]))
            return { input, positions: patterns.map((pattern) => outs.includes(pattern[0])) }
        })
    if (!maps.some((map) => map.input === values[0]))
        maps.push({ input: values[0], positions: patterns.map(() => true) })
    return {
        n,
        values,
        periodic: xmlBoolAttr(start, "periodic", true),
        shannon: xmlBoolAttr(start, "shannon", false),
        tries: Number(xmlAttr(start, "tries", "1000")),
        patterns,
        weights,
        propagator,
        maps,
    }
}

function convchainFromElement(elementXml, inheritedSymmetry, options) {
    const start = xmlRootStartTag(elementXml)
    const sample = xmlAttr(start, "sample")
    const on = xmlAttr(start, "on")
    const black = xmlAttr(start, "black")
    const white = xmlAttr(start, "white")
    if (!sample) throw new Error("convchain missing sample attribute")
    if (!on) throw new Error("convchain missing on attribute")
    if (!black) throw new Error("convchain missing black attribute")
    if (!white) throw new Error("convchain missing white attribute")
    const samplePng = options?.loadSamplePng?.(sample)
    if (!samplePng) throw new Error(`convchain sample ${sample} unavailable; pass loadSamplePng option`)
    const n = Number(xmlAttr(start, "n", "3"))
    return {
        n,
        temperature: Number(xmlAttr(start, "temperature", "1")),
        black,
        white,
        on,
        weights: convchainWeightsFromSample(samplePng, n, xmlAttr(start, "symmetry", inheritedSymmetry), options),
    }
}

function convolutionFromElement(elementXml) {
    const start = xmlRootStartTag(elementXml)
    const direct = xmlDirectChildTags(elementXml)
    const unsupported = direct.map((childXml) => xmlRootTag(childXml)).filter((childTag) => childTag !== "rule")
    if (unsupported.length > 0)
        throw new Error(`convolution has unsupported direct children: ${unsupported.join(", ")}`)
    const loadRule = (ruleXml) => {
        const tag = xmlRootStartTag(ruleXml)
        const input = xmlAttr(tag, "in")
        const output = xmlAttr(tag, "out")
        if (!input) throw new Error("convolution rule missing in attribute")
        if (!output) throw new Error("convolution rule missing out attribute")
        return {
            input,
            output,
            values: xmlAttr(tag, "values", ""),
            sum: xmlAttr(tag, "sum", ""),
            probability: Number(xmlAttr(tag, "p", "1")),
        }
    }
    const rules = direct.length > 0 ? direct.map(loadRule) : [loadRule(elementXml)]
    return { neighborhood: xmlAttr(start, "neighborhood", ""), periodic: xmlBoolAttr(start, "periodic", false), rules }
}

export function encodeMjirV1({
    values,
    node = "one",
    rules,
    fields = [],
    temperature = 0,
    observations = [],
    search,
    children,
    unions = [],
}) {
    const valueBytes = [...textEncoder.encode(values.replaceAll(" ", ""))]
    const nodeOps = (kind, steps, nodeFields = [], nodeTemperature = 0, nodeObservations = [], nodeSearch) => [
        { op: "node", kind, steps: steps ?? 0 },
        ...(nodeTemperature ? [{ op: "temperature", value: nodeTemperature }] : []),
        ...(nodeSearch?.enabled ? [{ op: "search", ...nodeSearch }] : []),
        ...nodeFields.map((field) => ({ op: "field", ...field })),
        ...nodeObservations.map((observation) => ({ op: "observe", ...observation })),
    ]
    const childPayloadOps = (child) => [
        ...(child.path ? [{ op: "path", ...child.path }] : []),
        ...(child.convolution ? [{ op: "convolution", ...child.convolution }] : []),
        ...(child.convchain ? [{ op: "convchain", ...child.convchain }] : []),
        ...(child.wfc ? [{ op: "wfc", ...child.wfc }] : []),
        ...(child.map ? [{ op: "map", ...child.map }] : []),
    ]
    const childOps = (child) => {
        const unionOps = (child.unions ?? []).map((union) => ({ op: "union", ...union }))
        if (child.children || child.map || child.wfc)
            return [
                ...nodeOps(child.node, child.steps, child.fields, child.temperature, child.observations, child.search),
                ...childPayloadOps(child),
                ...unionOps,
                ...(child.children ?? []).flatMap(childOps),
                { op: "end" },
            ]
        return [
            ...nodeOps(child.node, child.steps, child.fields, child.temperature, child.observations, child.search),
            ...childPayloadOps(child),
            ...unionOps,
            ...child.rules,
        ]
    }
    const bodyOps = children
        ? [{ op: "node", kind: node, steps: 0 }, ...children.flatMap(childOps)]
        : node === "one" && fields.length === 0 && observations.length === 0 && temperature === 0 && !search?.enabled
          ? rules
          : [...nodeOps(node, 0, fields, temperature, observations, search), ...rules]
    const ops = [...unions.map((union) => ({ op: "union", ...union })), ...bodyOps]
    const bytes = []
    bytes.push("M".charCodeAt(0), "J".charCodeAt(0), "I".charCodeAt(0), "R".charCodeAt(0))
    u32le(bytes, 1)
    u32le(bytes, valueBytes.length)
    bytes.push(...valueBytes)
    u32le(bytes, ops.length)

    for (const op of ops) {
        if (op.op === "node") {
            const kinds = {
                one: 1,
                all: 2,
                prl: 3,
                markov: 4,
                sequence: 5,
                path: 6,
                convolution: 7,
                convchain: 8,
                wfc: 9,
                map: 10,
            }
            if (!kinds[op.kind]) throw new Error(`unsupported node kind: ${op.kind}`)
            u32le(bytes, 100)
            u32le(bytes, kinds[op.kind])
            u32le(bytes, op.steps ?? 0)
            continue
        }
        if (op.op === "union") {
            const valuesBytes = [...textEncoder.encode(op.values)]
            u32le(bytes, 101)
            bytes.push(op.symbol.charCodeAt(0))
            u32le(bytes, valuesBytes.length)
            bytes.push(...valuesBytes)
            continue
        }
        if (op.op === "end") {
            u32le(bytes, 102)
            continue
        }
        if (op.op === "field") {
            const toBytes = [...textEncoder.encode(op.to ?? "")]
            const fromBytes = [...textEncoder.encode(op.from ?? "")]
            const onBytes = [...textEncoder.encode(op.on ?? "")]
            u32le(bytes, 103)
            bytes.push(op.for.charCodeAt(0))
            u32le(bytes, op.recompute ? 1 : 0)
            u32le(bytes, op.essential ? 1 : 0)
            u32le(bytes, toBytes.length)
            bytes.push(...toBytes)
            u32le(bytes, fromBytes.length)
            bytes.push(...fromBytes)
            u32le(bytes, onBytes.length)
            bytes.push(...onBytes)
            continue
        }
        if (op.op === "temperature") {
            u32le(bytes, 104)
            f64le(bytes, op.value)
            continue
        }
        if (op.op === "search") {
            u32le(bytes, 111)
            u32le(bytes, op.enabled ? 1 : 0)
            u32le(bytes, op.limit ?? -1)
            f64le(bytes, op.depthCoefficient ?? 0.5)
            continue
        }
        if (op.op === "observe") {
            const fromBytes = [...textEncoder.encode(op.from ?? "")]
            const toBytes = [...textEncoder.encode(op.to)]
            u32le(bytes, 105)
            bytes.push(op.value.charCodeAt(0))
            u32le(bytes, fromBytes.length)
            bytes.push(...fromBytes)
            u32le(bytes, toBytes.length)
            bytes.push(...toBytes)
            continue
        }
        if (op.op === "convolution") {
            const neighborhoodBytes = [...textEncoder.encode(op.neighborhood ?? "")]
            u32le(bytes, 107)
            u32le(bytes, neighborhoodBytes.length)
            bytes.push(...neighborhoodBytes)
            u32le(bytes, op.periodic ? 1 : 0)
            u32le(bytes, op.rules.length)
            for (const rule of op.rules) {
                const valuesBytes = [...textEncoder.encode(rule.values ?? "")]
                const sumsBytes = [...textEncoder.encode(rule.sum ?? "")]
                bytes.push(rule.input.charCodeAt(0), rule.output.charCodeAt(0))
                f64le(bytes, rule.probability ?? 1)
                u32le(bytes, valuesBytes.length)
                bytes.push(...valuesBytes)
                u32le(bytes, sumsBytes.length)
                bytes.push(...sumsBytes)
            }
            continue
        }
        if (op.op === "convchain") {
            u32le(bytes, 108)
            u32le(bytes, op.n)
            f64le(bytes, op.temperature ?? 1)
            bytes.push(op.black.charCodeAt(0), op.white.charCodeAt(0), op.on.charCodeAt(0))
            u32le(bytes, op.weights.length)
            for (const weight of op.weights) f64le(bytes, weight)
            continue
        }
        if (op.op === "wfc") {
            const valuesBytes = [...textEncoder.encode(op.values)]
            u32le(bytes, op.tile ? 112 : 109)
            if (op.tile) {
                u32le(bytes, op.tileS)
                u32le(bytes, op.tileSz)
                u32le(bytes, op.overlap ?? 0)
                u32le(bytes, op.overlapz ?? 0)
            } else u32le(bytes, op.n)
            u32le(bytes, op.periodic ? 1 : 0)
            u32le(bytes, op.shannon ? 1 : 0)
            u32le(bytes, op.tries ?? 1000)
            u32le(bytes, valuesBytes.length)
            bytes.push(...valuesBytes)
            u32le(bytes, op.patterns.length)
            for (let i = 0; i < op.patterns.length; i++) {
                f64le(bytes, op.weights[i])
                bytes.push(...op.patterns[i])
            }
            u32le(bytes, op.propagator.length)
            for (const dir of op.propagator)
                for (const list of dir) {
                    u32le(bytes, list.length)
                    for (const value of list) u32le(bytes, value)
                }
            u32le(bytes, op.maps.length)
            for (const map of op.maps) {
                bytes.push(map.input.charCodeAt(0))
                for (const present of map.positions) bytes.push(present ? 1 : 0)
            }
            continue
        }
        if (op.op === "map") {
            const valuesBytes = [...textEncoder.encode(op.values)]
            u32le(bytes, 110)
            for (const pair of [op.sx, op.sy, op.sz]) {
                u32le(bytes, pair.n)
                u32le(bytes, pair.d)
            }
            u32le(bytes, valuesBytes.length)
            bytes.push(...valuesBytes)
            u32le(bytes, op.unions.length)
            for (const union of op.unions) {
                bytes.push(union.symbol.charCodeAt(0))
                const unionValues = [...textEncoder.encode(union.values)]
                u32le(bytes, unionValues.length)
                bytes.push(...unionValues)
            }
            u32le(bytes, op.rules.length)
            for (const rule of op.rules) {
                const input = parsePattern(rule.input)
                const output = parsePattern(rule.output)
                const symmetryBytes = [...textEncoder.encode(rule.symmetry ?? "")]
                u32le(bytes, input.width)
                u32le(bytes, input.height)
                u32le(bytes, input.depth)
                u32le(bytes, output.width)
                u32le(bytes, output.height)
                u32le(bytes, output.depth)
                f64le(bytes, rule.probability ?? 1)
                u32le(bytes, symmetryBytes.length)
                bytes.push(...symmetryBytes)
                bytes.push(...input.data, ...output.data)
            }
            continue
        }
        if (op.op === "path") {
            const fromBytes = [...textEncoder.encode(op.from)]
            const toBytes = [...textEncoder.encode(op.to)]
            const onBytes = [...textEncoder.encode(op.on)]
            const colorBytes = [...textEncoder.encode(op.color ?? op.from[0])]
            u32le(bytes, 106)
            u32le(bytes, fromBytes.length)
            bytes.push(...fromBytes)
            u32le(bytes, toBytes.length)
            bytes.push(...toBytes)
            u32le(bytes, onBytes.length)
            bytes.push(...onBytes)
            bytes.push(colorBytes[0])
            u32le(bytes, op.inertia ? 1 : 0)
            u32le(bytes, op.longest ? 1 : 0)
            u32le(bytes, op.edges ? 1 : 0)
            u32le(bytes, op.vertices ? 1 : 0)
            continue
        }
        if (op.op !== "pattern") throw new Error(`unsupported rule op: ${op.op}`)
        const input = parsePattern(op.input)
        const output = parsePattern(op.output)
        const symmetryBytes = [...textEncoder.encode(op.symmetry ?? "")]
        bytes.push(2, 0, 0, 0) // op = pattern rule
        u32le(bytes, input.width)
        u32le(bytes, input.height)
        u32le(bytes, input.depth)
        u32le(bytes, output.width)
        u32le(bytes, output.height)
        u32le(bytes, output.depth)
        f64le(bytes, op.probability ?? 1)
        u32le(bytes, symmetryBytes.length)
        bytes.push(...symmetryBytes)
        bytes.push(...input.data)
        bytes.push(...output.data)
    }
    return bytes
}

export function xmlRuleTags(xml) {
    return [...xml.matchAll(/<rule\b([^>]*)\/?\s*>/g)].map((match) => match[0])
}

export function xmlUnionTags(xml) {
    return [...xml.matchAll(/<union\b([^>]*)\/?\s*>/g)].map((match) => match[0])
}

function unionsFromXml(xml) {
    return xmlUnionTags(xml).map((tag) => {
        const symbol = xmlAttr(tag, "symbol")
        const values = xmlAttr(tag, "values")
        if (!symbol) throw new Error("union missing symbol attribute")
        if (!values) throw new Error("union missing values attribute")
        return { symbol, values }
    })
}

export function xmlDirectChildTags(xml) {
    const source = xml.replace(/<!--([\s\S]*?)-->/g, "")
    const rootStart = xmlRootStartTag(source)
    const root = xmlRootTag(source)
    const closeRoot = source.lastIndexOf(`</${root}>`)
    const inner = closeRoot >= 0 ? source.slice(rootStart.length, closeRoot) : source.slice(rootStart.length)
    const children = []
    let i = 0
    while (i < inner.length) {
        const start = inner.indexOf("<", i)
        if (start < 0) break
        if (inner[start + 1] === "/") {
            i = start + 2
            continue
        }
        const headEnd = inner.indexOf(">", start)
        if (headEnd < 0) break
        const name = inner
            .slice(start + 1, headEnd)
            .trim()
            .match(/^([a-zA-Z0-9_-]+)/)?.[1]
        if (!name) {
            i = headEnd + 1
            continue
        }
        if (inner[headEnd - 1] === "/") {
            children.push(inner.slice(start, headEnd + 1))
            i = headEnd + 1
            continue
        }

        const tagRe = /<\/?([a-zA-Z0-9_-]+)\b[^>]*>/g
        tagRe.lastIndex = headEnd + 1
        let depth = 1
        let closeEnd = -1
        for (let match; (match = tagRe.exec(inner)); ) {
            if (match[1] !== name) continue
            const full = match[0]
            if (full.startsWith("</")) depth -= 1
            else if (!full.endsWith("/>")) depth += 1
            if (depth === 0) {
                closeEnd = tagRe.lastIndex
                break
            }
        }
        if (closeEnd < 0) break
        children.push(inner.slice(start, closeEnd))
        i = closeEnd
    }
    return children
}

export function xmlChildNodeTags(xml) {
    return xmlDirectChildTags(xml).filter((tag) => ["one", "all", "prl"].includes(xmlRootTag(tag)))
}

function nodeFromElement(elementXml, inheritedSymmetry = "", options = {}) {
    const tag = xmlRootTag(elementXml)
    const start = xmlRootStartTag(elementXml)
    const steps = Number(xmlAttr(start, "steps", "0"))
    if (tag === "path") {
        const path = pathFromElement(elementXml)
        return { node: tag, steps, rules: [], path }
    }
    if (tag === "convolution") {
        const convolution = convolutionFromElement(elementXml)
        return { node: tag, steps, rules: [], convolution }
    }
    if (tag === "convchain") {
        const convchain = convchainFromElement(elementXml, inheritedSymmetry, options)
        return { node: tag, steps, rules: [], convchain }
    }
    if (tag === "wfc") {
        const wfc = xmlAttr(start, "sample")
            ? wfcOverlapFromElement(elementXml, inheritedSymmetry, options)
            : tileWfcFromElement(elementXml, inheritedSymmetry, options)
        const direct = xmlDirectChildTags(elementXml)
        const unsupported = direct
            .map((childXml) => xmlRootTag(childXml))
            .filter(
                (childTag) =>
                    ![
                        "rule",
                        "union",
                        "one",
                        "all",
                        "prl",
                        "path",
                        "convolution",
                        "convchain",
                        "wfc",
                        "map",
                        "markov",
                        "sequence",
                    ].includes(childTag),
            )
        if (unsupported.length > 0) throw new Error(`wfc has unsupported direct children: ${unsupported.join(", ")}`)
        const nodeSymmetry = xmlAttr(start, "symmetry", inheritedSymmetry)
        const childOptions = { ...options, values: wfc.values }
        const children = direct
            .filter((childXml) => !["rule", "union"].includes(xmlRootTag(childXml)))
            .map((childXml) => nodeFromElement(childXml, nodeSymmetry, childOptions))
        const unions = unionsFromXml(elementXml)
        return children.length > 0
            ? { node: tag, steps, rules: [], wfc, unions, children }
            : { node: tag, steps, rules: [], wfc, unions }
    }
    if (tag === "map") {
        const map = mapFromElement(elementXml, inheritedSymmetry, options)
        return map.children.length > 0
            ? { node: tag, steps, rules: [], map, children: map.children }
            : { node: tag, steps, rules: [], map }
    }
    if (tag === "markov" || tag === "sequence") {
        const direct = xmlDirectChildTags(elementXml)
        const unsupported = direct
            .map((childXml) => xmlRootTag(childXml))
            .filter(
                (childTag) =>
                    ![
                        "one",
                        "all",
                        "prl",
                        "path",
                        "convolution",
                        "convchain",
                        "wfc",
                        "map",
                        "markov",
                        "sequence",
                        "union",
                    ].includes(childTag),
            )
        if (unsupported.length > 0)
            throw new Error(`${tag} child has unsupported direct children: ${unsupported.join(", ")}`)
        const nodeSymmetry = xmlAttr(start, "symmetry", inheritedSymmetry)
        const children = direct
            .filter((childXml) => xmlRootTag(childXml) !== "union")
            .map((childXml) => nodeFromElement(childXml, nodeSymmetry, options))
        if (children.length === 0) throw new Error(`child <${tag}> missing child nodes`)
        return { node: tag, steps, unions: unionsFromXml(elementXml), children }
    }
    // return {
    //     node: tag,
    //     steps,
    //     rules: rulesFromElement(elementXml, inheritedSymmetry, options),
    //     fields: fieldsFromElement(elementXml),
    //     observations: observationsFromElement(elementXml),
    //     search: searchFromElement(elementXml),
    //     temperature: Number(xmlAttr(start, "temperature", "0")),
    // }
    return {
        node: tag,
        steps,
        rules: rulesFromElement(elementXml, inheritedSymmetry, options),
        fields: fieldsFromElement(elementXml),
        observations: observationsFromElement(elementXml),
        search: searchFromElement(elementXml),
        temperature: Number(xmlAttr(start, "temperature", "0")),
        unions: unionsFromXml(elementXml),
    }
}

function fieldsFromElement(elementXml) {
    return xmlDirectChildTags(elementXml)
        .filter((childXml) => xmlRootTag(childXml) === "field")
        .map((fieldXml) => {
            const start = xmlRootStartTag(fieldXml)
            const forSymbol = xmlAttr(start, "for")
            const on = xmlAttr(start, "on")
            const to = xmlAttr(start, "to")
            const from = xmlAttr(start, "from")
            if (!forSymbol) throw new Error("child <field> missing for attribute")
            if (!on) throw new Error("child <field> missing on attribute")
            if (!to && !from) throw new Error("child <field> missing to/from attribute")
            return {
                for: forSymbol,
                on,
                to,
                from,
                recompute: xmlBoolAttr(start, "recompute", false),
                essential: xmlBoolAttr(start, "essential", false),
            }
        })
}

function pathFromElement(elementXml) {
    const start = xmlRootStartTag(elementXml)
    const from = xmlAttr(start, "from")
    const to = xmlAttr(start, "to")
    const on = xmlAttr(start, "on")
    if (!from) throw new Error("<path> missing from attribute")
    if (!to) throw new Error("<path> missing to attribute")
    if (!on) throw new Error("<path> missing on attribute")
    return {
        from,
        to,
        on,
        color: xmlAttr(start, "color", from[0]),
        inertia: xmlBoolAttr(start, "inertia", false),
        longest: xmlBoolAttr(start, "longest", false),
        edges: xmlBoolAttr(start, "edges", false),
        vertices: xmlBoolAttr(start, "vertices", false),
    }
}

function searchFromElement(elementXml) {
    const start = xmlRootStartTag(elementXml)
    if (!xmlBoolAttr(start, "search", false)) return undefined
    return {
        enabled: true,
        limit: Number(xmlAttr(start, "limit", "-1")),
        depthCoefficient: Number(xmlAttr(start, "depthCoefficient", "0.5")),
    }
}

function observationsFromElement(elementXml) {
    return xmlDirectChildTags(elementXml)
        .filter((childXml) => xmlRootTag(childXml) === "observe")
        .map((observeXml) => {
            const start = xmlRootStartTag(observeXml)
            const value = xmlAttr(start, "value")
            const to = xmlAttr(start, "to")
            if (!value) throw new Error("child <observe> missing value attribute")
            if (!to) throw new Error("child <observe> missing to attribute")
            return { value, from: xmlAttr(start, "from", ""), to }
        })
}

function loadRuleResourcePattern(file, legend, options) {
    const pattern = options?.loadRulePattern?.(file, legend, options.folder)
    if (pattern) return pattern
    if ((options?.depth ?? 1) > 1) {
        const vox = options?.loadRuleVox?.(file, options.folder)
        if (vox) return decodeVoxPattern(vox, legend)
    }
    const png = options?.loadRulePng?.(file, options.folder)
    if (png) return decodePngPattern(png, legend, options)
    const vox = options?.loadRuleVox?.(file, options.folder)
    if (vox) return decodeVoxPattern(vox, legend)
    throw new Error(`rule resource ${file} unavailable; pass loadRulePattern/loadRulePng/loadRuleVox option`)
}

function splitFileRulePattern(pattern) {
    if (pattern.width % 2 !== 0) throw new Error("file rule resource width must be even")
    const half = pattern.width / 2
    const input = []
    const output = []
    for (let z = 0; z < pattern.depth; z++)
        for (let y = 0; y < pattern.height; y++)
            for (let x = 0; x < half; x++) {
                input.push(pattern.data[x + y * pattern.width + z * pattern.width * pattern.height])
                output.push(pattern.data[x + half + y * pattern.width + z * pattern.width * pattern.height])
            }
    return {
        input: input.join(""),
        output: output.join(""),
        inputShape: { width: half, height: pattern.height, depth: pattern.depth },
        outputShape: { width: half, height: pattern.height, depth: pattern.depth },
    }
}

function encodePatternLiteral(data, shape) {
    const layers = []
    for (let z = shape.depth - 1; z >= 0; z--) {
        const rows = []
        for (let y = 0; y < shape.height; y++)
            rows.push(
                data.slice(
                    z * shape.width * shape.height + y * shape.width,
                    z * shape.width * shape.height + (y + 1) * shape.width,
                ),
            )
        layers.push(rows.join("/"))
    }
    return layers.join(" ")
}

function rulesFromElement(elementXml, inheritedSymmetry = "", options = {}) {
    const start = xmlRootStartTag(elementXml)
    for (const attr of ["fin", "fout"]) {
        if (xmlAttr(start, attr, "") !== "") throw new Error(`unsupported ${attr} attribute`)
    }
    const directChildren = xmlDirectChildTags(elementXml)
    const allowedChildren = new Set(["rule", "field", "observe", "union"])

    const unsupportedChildren = directChildren
        .map((childXml) => xmlRootTag(childXml))
        .filter((childTag) => !allowedChildren.has(childTag))

    if (unsupportedChildren.length > 0) {
        throw new Error(`unsupported children: ${unsupportedChildren.join(", ")}`)
    }
    const input = xmlAttr(start, "in")
    const output = xmlAttr(start, "out")
    const file = xmlAttr(start, "file")
    const legend = xmlAttr(start, "legend")
    const symmetry = xmlAttr(start, "symmetry", inheritedSymmetry)
    if (file) {
        if (!legend) throw new Error("file rule missing legend attribute")
        const split = splitFileRulePattern(loadRuleResourcePattern(file, legend, options))
        return [
            {
                op: "pattern",
                input: encodePatternLiteral(split.input, split.inputShape),
                output: encodePatternLiteral(split.output, split.outputShape),
                symmetry,
                probability: Number(xmlAttr(start, "p", "1")),
            },
        ]
    }
    if (input || output) {
        if (!input) throw new Error("missing in attribute")
        if (!output) throw new Error("missing out attribute")
        return [{ op: "pattern", input, output, symmetry, probability: Number(xmlAttr(start, "p", "1")) }]
    }

    const ruleTags = directChildren.filter((childXml) => xmlRootTag(childXml) === "rule")
    const rules = []
    for (const ruleTag of ruleTags) {
        const ruleFile = xmlAttr(ruleTag, "file")
        const ruleInput = xmlAttr(ruleTag, "in")
        const ruleOutput = xmlAttr(ruleTag, "out")
        if (ruleFile) {
            const ruleLegend = xmlAttr(ruleTag, "legend")
            if (!ruleLegend) throw new Error("child <rule file> missing legend attribute")
            const split = splitFileRulePattern(loadRuleResourcePattern(ruleFile, ruleLegend, options))
            rules.push({
                op: "pattern",
                input: encodePatternLiteral(split.input, split.inputShape),
                output: encodePatternLiteral(split.output, split.outputShape),
                symmetry: xmlAttr(ruleTag, "symmetry", symmetry),
                probability: Number(xmlAttr(ruleTag, "p", "1")),
            })
            continue
        }
        if (!ruleInput) throw new Error("child <rule> missing in attribute")
        if (!ruleOutput) throw new Error("child <rule> missing out attribute")
        rules.push({
            op: "pattern",
            input: ruleInput,
            output: ruleOutput,
            symmetry: xmlAttr(ruleTag, "symmetry", symmetry),
            probability: Number(xmlAttr(ruleTag, "p", "1")),
        })
    }
    return rules
}

export function compileXmlToMjir(xml, options = {}) {
    const tag = xmlRootTag(xml)
    if (
        tag !== "one" &&
        tag !== "all" &&
        tag !== "prl" &&
        tag !== "markov" &&
        tag !== "sequence" &&
        tag !== "path" &&
        tag !== "convolution" &&
        tag !== "convchain" &&
        tag !== "wfc" &&
        tag !== "map"
    ) {
        throw new Error(
            `MJIR v1 compiler supports only root <one>/<all>/<prl>/<markov>/<sequence>/<path>/<convolution>/<convchain>/<wfc>/<map>, got ${tag || "unknown"}`,
        )
    }
    const rootStart = xmlRootStartTag(xml)
    const values = xmlAttr(rootStart, "values")
    if (!values) throw new Error("missing values attribute")

    const rootSymmetry = xmlAttr(rootStart, "symmetry", "")
    options = { ...options, folder: xmlAttr(rootStart, "folder", options.folder ?? "") }
    if (tag === "markov" || tag === "sequence") {
        const direct = xmlDirectChildTags(xml)
        const unsupported = direct
            .map((childXml) => xmlRootTag(childXml))
            .filter(
                (childTag) =>
                    ![
                        "one",
                        "all",
                        "prl",
                        "path",
                        "convolution",
                        "convchain",
                        "wfc",
                        "map",
                        "markov",
                        "sequence",
                        "union",
                    ].includes(childTag),
            )
        if (unsupported.length > 0)
            throw new Error(`${tag} root has unsupported direct children: ${unsupported.join(", ")}`)
        const children = direct
            .filter((childXml) => xmlRootTag(childXml) !== "union")
            .map((childXml) => nodeFromElement(childXml, rootSymmetry, options))
        if (children.length === 0) throw new Error(`${tag} root missing child nodes`)
        for (const child of children)
            if (
                !child.children &&
                !child.path &&
                !child.convolution &&
                !child.convchain &&
                !child.wfc &&
                !child.map &&
                child.rules.length === 0
            )
                throw new Error(`child <${child.node}> missing in/out attributes or child <rule> elements`)
        return encodeMjirV1({ values, node: tag, children, unions: unionsFromXml(xml) })
    }

    if (tag === "path") {
        return encodeMjirV1({
            values,
            node: tag,
            rules: [{ op: "path", ...pathFromElement(xml) }],
            unions: unionsFromXml(xml),
        })
    }
    if (tag === "convolution") {
        return encodeMjirV1({
            values,
            node: tag,
            rules: [{ op: "convolution", ...convolutionFromElement(xml) }],
            unions: unionsFromXml(xml),
        })
    }
    if (tag === "convchain") {
        return encodeMjirV1({
            values,
            node: tag,
            rules: [{ op: "convchain", ...convchainFromElement(xml, rootSymmetry, options) }],
            unions: unionsFromXml(xml),
        })
    }
    if (tag === "wfc") {
        return encodeMjirV1({
            values,
            node: tag,
            rules: [{ op: "wfc", ...wfcOverlapFromElement(xml, rootSymmetry, options) }],
            unions: unionsFromXml(xml),
        })
    }
    if (tag === "map") {
        return encodeMjirV1({
            values,
            node: tag,
            rules: [{ op: "map", ...mapFromElement(xml, rootSymmetry, options) }],
            unions: unionsFromXml(xml),
        })
    }

    const rules = rulesFromElement(xml, rootSymmetry, options)
    if (rules.length === 0) throw new Error("missing in/out attributes or child <rule> elements")
    return encodeMjirV1({
        values,
        node: tag,
        rules,
        fields: fieldsFromElement(xml),
        observations: observationsFromElement(xml),
        search: searchFromElement(xml),
        temperature: Number(xmlAttr(rootStart, "temperature", "0")),
        unions: unionsFromXml(xml),
    })
}

export function compileMjirV1FromXml(xml, options = {}) {
    return compileXmlToMjir(xml, options)
}

export function initialGrid(width, height, depth, fillIndex = 0) {
    return Array.from({ length: width * height * depth }, () => fillIndex)
}

export function initialGridFromXml(xml, width, height, depth) {
    const cells = initialGrid(width, height, depth, 0)
    if (xmlBoolAttr(xml, "origin", false)) {
        const index = Math.floor(width / 2) + Math.floor(height / 2) * width + Math.floor(depth / 2) * width * height
        cells[index] = 1
    }
    return cells
}

export function parseMjstate(text) {
    const lines = text.trimEnd().split(/\r?\n/)
    if (lines[0] !== "MJSTATE 1") throw new Error("not an MJSTATE 1 file")
    const size = lines[1].match(/^size\s+(\d+)\s+(\d+)\s+(\d+)$/)
    if (!size) throw new Error("MJSTATE missing size line")
    const width = Number(size[1])
    const height = Number(size[2])
    const depth = Number(size[3])
    const legend = lines[2].replace(/^legend\s+/, "")
    const cells = []
    for (const line of lines.slice(3)) {
        if (line.startsWith("z ")) continue
        for (const ch of line) {
            const idx = legend.indexOf(ch)
            if (idx < 0) throw new Error(`cell symbol ${ch} is absent from legend ${legend}`)
            cells.push(idx)
        }
    }
    return { width, height, depth, values: legend, cells }
}
