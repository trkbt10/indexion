// RFC 3492 section 5 parameter values for Punycode.
const base = 36
const tmin = 1
const tmax = 26
const skew = 38
const damp = 700
const initial_bias = 72
const initial_n = 0x80
const delimiter = 0x2d

/**
 * RFC 3492 appendix C sample implementation constants.
 */
const maxInt = 0x7fffffff
const aceMaxLength = 256
const unicodeMaxLength = 256

/**
 * RFC 3492 section 4 bootstring parameters gathered as a single value object.
 */
export const bootstringParameters = {
  base,
  tmin,
  tmax,
  skew,
  damp,
  initial_bias,
  initial_n,
  delimiter,
}

/**
 * RFC 3492 section 6.4 overflow handling constants.
 */
export const overflowHandling = {
  maxInt,
  aceMaxLength,
  unicodeMaxLength,
}

function isBasicCodePoint(cp: number): boolean {
  return cp < 0x80
}

function isDelimiter(cp: number): boolean {
  return cp === delimiter
}

/**
 * RFC 3492 appendix C decode_digit helper.
 */
export function decodeDigit(cp: number): number {
  if (cp >= 0x30 && cp <= 0x39) return cp - 22
  if (cp >= 0x41 && cp <= 0x5a) return cp - 65
  if (cp >= 0x61 && cp <= 0x7a) return cp - 97
  return base
}

/**
 * RFC 3492 appendix C encode_digit helper.
 */
export function encodeDigit(digit: number, uppercase = false): string {
  if (digit < 26) {
    return String.fromCharCode(digit + (uppercase ? 0x41 : 0x61))
  }
  if (digit < 36) {
    return String.fromCharCode(digit - 26 + 0x30)
  }
  throw new RangeError("invalid punycode digit")
}

/**
 * RFC 3492 appendix C encode_basic helper.
 */
function encodeBasic(cp: number, uppercase = false): string {
  if (!isBasicCodePoint(cp)) {
    throw new RangeError("basic code point expected")
  }
  const lower = cp >= 0x41 && cp <= 0x5a ? cp + 0x20 : cp
  if (uppercase && lower >= 0x61 && lower <= 0x7a) {
    return String.fromCharCode(lower - 0x20)
  }
  return String.fromCharCode(lower)
}

/**
 * RFC 3492 section 6.1 bias adaptation function.
 */
export function adapt(delta: number, numPoints: number, firstTime: boolean): number {
  let scaled = firstTime ? Math.floor(delta / damp) : delta >> 1
  scaled += Math.floor(scaled / numPoints)
  let k = 0
  while (scaled > Math.floor(((base - tmin) * tmax) / 2)) {
    scaled = Math.floor(scaled / (base - tmin))
    k += base
  }
  return k + Math.floor(((base - tmin + 1) * scaled) / (scaled + skew))
}

/**
 * RFC 3492 sections 3.3 and 6 threshold function.
 */
function threshold(k: number, bias: number): number {
  const raw = k - bias
  if (raw < tmin) return tmin
  if (raw > tmax) return tmax
  return raw
}

/**
 * RFC 3492 section 6.4 overflow handling guard.
 */
function guardAdd(a: number, b: number): number {
  if (b > maxInt - a) {
    throw new RangeError("punycode overflow")
  }
  return a + b
}

/**
 * RFC 3492 section 6.4 overflow handling guard for A + (B * C).
 */
function guardMulAdd(a: number, b: number, c: number): number {
  if (c !== 0 && b > Math.floor((maxInt - a) / c)) {
    throw new RangeError("punycode overflow")
  }
  return a + b * c
}

/**
 * RFC 3492 section 6.4 ACE label length guard.
 */
function assertAceLabelLength(label: string): void {
  if (label.length > 63) {
    throw new RangeError("punycode overflow: ACE label exceeds 63 characters")
  }
}

/**
 * RFC 3492 appendix C Unicode input length guard.
 */
function assertUnicodeLabelLength(codePoints: Array<number>): void {
  if (codePoints.length > unicodeMaxLength) {
    throw new RangeError("punycode overflow: Unicode label exceeds implementation bound")
  }
}

/**
 * RFC 3492 section 2 terminology helper.
 */
function toCodePoints(input: string): Array<number> {
  return Array.from(input, (ch) => ch.codePointAt(0)!)
}

/**
 * RFC 3492 section 2 terminology helper.
 */
function fromCodePoints(codePoints: Array<number>): string {
  return String.fromCodePoint(...codePoints)
}

/**
 * RFC 3492 section 3.3 generalized variable-length integer decoding.
 */
function decodeGeneralizedVariableInteger(
  input: string,
  start: number,
  initial: number,
  bias: number,
): { value: number; nextIndex: number } {
  let i = initial
  let w = 1
  let index = start
  for (let k = base; ; k += base) {
    if (index >= input.length) {
      throw new RangeError("punycode bad input")
    }
    const digit = decodeDigit(input.codePointAt(index)!)
    if (digit >= base) {
      throw new RangeError("punycode bad input")
    }
    i = guardMulAdd(i, digit, w)
    const t = threshold(k, bias)
    index += 1
    if (digit < t) {
      return { value: i, nextIndex: index }
    }
    w = guardMulAdd(0, w, base - t)
  }
}

/**
 * RFC 3492 section 3.3 generalized variable-length integer encoding.
 */
function encodeGeneralizedVariableInteger(delta: number, bias: number): string {
  let q = delta
  let output = ""
  for (let k = base; ; k += base) {
    const t = threshold(k, bias)
    if (q < t) {
      output += encodeDigit(q)
      return output
    }
    output += encodeDigit(t + ((q - t) % (base - t)))
    q = Math.floor((q - t) / (base - t))
  }
}

/**
 * RFC 3492 section 6.2 decoding procedure.
 */
export function decodePunycode(input: string): string {
  assertAceLabelLength(input)
  let n = initial_n
  let i = 0
  let bias = initial_bias
  const output: Array<number> = []
  const basicLength = input.lastIndexOf(String.fromCharCode(delimiter))
  let index = 0

  if (basicLength >= 0) {
    for (let j = 0; j < basicLength; j += 1) {
      const cp = input.codePointAt(j)!
      if (!isBasicCodePoint(cp)) {
        throw new RangeError("punycode bad input")
      }
      output.push(cp)
    }
    index = basicLength + 1
  }

  while (index < input.length) {
    const oldi = i
    const decoded = decodeGeneralizedVariableInteger(input, index, i, bias)
    i = decoded.value
    index = decoded.nextIndex
    bias = adapt(i - oldi, output.length + 1, oldi === 0)
    n = guardAdd(n, Math.floor(i / (output.length + 1)))
    i %= output.length + 1
    if (isBasicCodePoint(n)) {
      throw new RangeError("punycode bad input")
    }
    output.splice(i, 0, n)
    i += 1
  }

  assertUnicodeLabelLength(output)
  return fromCodePoints(output)
}

/**
 * RFC 3492 section 6.3 encoding procedure.
 */
export function encodePunycode(input: string): string {
  const codePoints = toCodePoints(input)
  assertUnicodeLabelLength(codePoints)

  let n = initial_n
  let delta = 0
  let bias = initial_bias
  let output = ""

  let h = 0
  for (const cp of codePoints) {
    if (isBasicCodePoint(cp)) {
      output += String.fromCodePoint(cp)
      h += 1
    }
  }
  const b = h
  if (b > 0) {
    output += String.fromCharCode(delimiter)
  }

  while (h < codePoints.length) {
    let m = maxInt
    for (const cp of codePoints) {
      if (cp >= n && cp < m) {
        m = cp
      }
    }

    delta = guardMulAdd(delta, m - n, h + 1)
    n = m

    for (const cp of codePoints) {
      if (cp < n) {
        delta = guardAdd(delta, 1)
      }
      if (cp === n) {
        output += encodeGeneralizedVariableInteger(delta, bias)
        bias = adapt(delta, h + 1, h === b)
        delta = 0
        h += 1
      }
    }

    delta = guardAdd(delta, 1)
    n = guardAdd(n, 1)
  }

  assertAceLabelLength(output)
  return output
}

/**
 * RFC 3492 section 1 interaction with ACE labels.
 */
export function encodePunycodeLabel(label: string): string {
  return "xn--" + encodePunycode(label)
}

/**
 * RFC 3492 section 1 interaction with ACE labels.
 */
export function decodePunycodeLabel(label: string): string {
  if (!label.startsWith("xn--")) {
    throw new RangeError("punycode label must start with xn--")
  }
  return decodePunycode(label.slice(4))
}

function fromHexCodePoints(values: Array<number>): string {
  return String.fromCodePoint(...values)
}

/**
 * RFC 3492 section 7.1 sample strings.
 */
export const sampleStrings: Array<{ name: string; unicode: string; ascii: string }> = [
  {
    name: "Arabic (Egyptian)",
    unicode: fromHexCodePoints([0x0644, 0x064A, 0x0647, 0x0645, 0x0627, 0x0628, 0x062A, 0x0643, 0x0644, 0x0645, 0x0648, 0x0634, 0x0639, 0x0631, 0x0628, 0x064A, 0x061F]),
    ascii: "egbpdaj6bu4bxfgehfvwxn",
  },
  {
    name: "Chinese (simplified)",
    unicode: fromHexCodePoints([0x4ED6, 0x4EEC, 0x4E3A, 0x4EC0, 0x4E48, 0x4E0D, 0x8BF4, 0x4E2D, 0x6587]),
    ascii: "ihqwcrb4cv8a8dqg056pqjye",
  },
  {
    name: "Chinese (traditional)",
    unicode: fromHexCodePoints([0x4ED6, 0x5011, 0x7232, 0x4EC0, 0x9EBD, 0x4E0D, 0x8AAA, 0x4E2D, 0x6587]),
    ascii: "ihqwctvzc91f659drss3x8bo0yb",
  },
  {
    name: "Spanish",
    unicode: "PorquénopuedensimplementehablarenEspañol",
    ascii: "PorqunopuedensimplementehablarenEspaol-fmd56a",
  },
  {
    name: "Japanese",
    unicode: fromHexCodePoints([0x0033, 0x5E74, 0x0042, 0x7D44, 0x91D1, 0x516B, 0x5148, 0x751F]),
    ascii: "3B-ww4c5e180e575a65lsy2b",
  },
  {
    name: "ASCII edge case",
    unicode: "-> $1.00 <-",
    ascii: "-> $1.00 <--",
  },
]
