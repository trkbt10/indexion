/**
 * RFC 2795 section 5.1 KEEPER message request codes.
 */
const REQUEST_STATUS = 1
const REQUEST_HEARTBEAT = 2
const REQUEST_WAKEUP = 3
const REQUEST_TYPE = 4
const REQUEST_FASTER = 5
const REQUEST_TRANSCRIPT = 6
const REQUEST_STOP = 7

/**
 * RFC 2795 section 5.2 KEEPER message response codes.
 */
const RESPONSE_ASLEEP = 1
const RESPONSE_GONE = 2
const RESPONSE_DISTRACTED = 3
const RESPONSE_NORESPONSE = 4
const RESPONSE_ALIVE = 5
const RESPONSE_DEAD = 6
const RESPONSE_ACCEPT = 7
const RESPONSE_REFUSE = 8

/**
 * RFC 2795 sections 3, 6, 7, and 8 protocol numbers.
 */
const IMPS_VERSION = 1
const IMPS_KEEPER_PROTOCOL = 1
const IMPS_CHIMP_PROTOCOL = 2
const IMPS_IAMB_PENT_PROTOCOL = 5
const IMPS_PAN_PROTOCOL = 10
const IMPS_UINT32_BITS = 32
const IMPS_RESERVED = 0

/**
 * RFC 2795 sections 3, 5, 6, 7, and 8 protocol constants.
 */
export const protocolNumbers = {
  impsVersion: IMPS_VERSION,
  keeper: IMPS_KEEPER_PROTOCOL,
  chimp: IMPS_CHIMP_PROTOCOL,
  iambPent: IMPS_IAMB_PENT_PROTOCOL,
  pan: IMPS_PAN_PROTOCOL,
  uint32Bits: IMPS_UINT32_BITS,
  reserved: IMPS_RESERVED,
}

/**
 * RFC 2795 section 5.1 KEEPER request code table.
 */
export const keeperRequestCodes = {
  STATUS: REQUEST_STATUS,
  HEARTBEAT: REQUEST_HEARTBEAT,
  WAKEUP: REQUEST_WAKEUP,
  TYPE: REQUEST_TYPE,
  FASTER: REQUEST_FASTER,
  TRANSCRIPT: REQUEST_TRANSCRIPT,
  STOP: REQUEST_STOP,
}

/**
 * RFC 2795 section 5.1 KEEPER request code ranges.
 */
export const keeperRequestCodeRanges = {
  FUTURE: "8-512",
  USER: "513+",
}

/**
 * RFC 2795 section 5.2 KEEPER response code table.
 */
export const keeperResponseCodes = {
  ASLEEP: RESPONSE_ASLEEP,
  GONE: RESPONSE_GONE,
  DISTRACTED: RESPONSE_DISTRACTED,
  NORESPONSE: RESPONSE_NORESPONSE,
  ALIVE: RESPONSE_ALIVE,
  DEAD: RESPONSE_DEAD,
  ACCEPT: RESPONSE_ACCEPT,
  REFUSE: RESPONSE_REFUSE,
}

/**
 * RFC 2795 section 5.2 KEEPER response code ranges.
 */
export const keeperResponseCodeRanges = {
  FUTURE: "9-512",
  USER: "513+",
}

/**
 * RFC 2795 section 3 IMPS packet structure.
 */
interface ImpsPacket {
  version: number
  sequenceNumber: number
  protocolNumber: number
  reserved: number
  size: number
  source: bigint
  destination: bigint
  data: Uint8Array
}

/**
 * RFC 2795 section 4 I-TAG encoding preview.
 */
export function encodeITagBits(id: bigint): { metaSizeBits: string; sizeBits: string; idBytes: number } {
  const hex = id.toString(16)
  const idBytes = Math.max(1, Math.ceil(hex.length / 2))
  const sizeBits = idBytes.toString(2)
  return {
    metaSizeBits: `${"1".repeat(sizeBits.length)}0`,
    sizeBits,
    idBytes,
  }
}

function bitStringToBytes(bits: string): Uint8Array {
  const padded = bits.padEnd(Math.ceil(bits.length / 8) * 8, "0")
  const bytes = new Uint8Array(padded.length / 8)
  for (let i = 0; i < bytes.length; i += 1) {
    bytes[i] = parseInt(padded.slice(i * 8, i * 8 + 8), 2)
  }
  return bytes
}

function bytesToBitString(bytes: Uint8Array): string {
  return Array.from(bytes, (value) => value.toString(2).padStart(8, "0")).join("")
}

function bigintToBytes(value: bigint, width: number): Uint8Array {
  const bytes = new Uint8Array(width)
  let current = value
  for (let i = width - 1; i >= 0; i -= 1) {
    bytes[i] = Number(current & 0xffn)
    current >>= 8n
  }
  return bytes
}

function bytesToBigInt(bytes: Uint8Array): bigint {
  let value = 0n
  for (const byte of bytes) {
    value = (value << 8n) | BigInt(byte)
  }
  return value
}

/**
 * RFC 2795 section 4 I-TAG encoding.
 */
export function encodeITag(id: bigint): Uint8Array {
  const bits = encodeITagBits(id)
  const idBits = Array.from(bigintToBytes(id, bits.idBytes), (value) =>
    value.toString(2).padStart(8, "0"),
  ).join("")
  return bitStringToBytes(bits.metaSizeBits + bits.sizeBits + idBits)
}

/**
 * RFC 2795 section 4 I-TAG decoding.
 */
export function decodeITag(
  data: Uint8Array,
  offset = 0,
): { value: bigint; bytesRead: number } {
  const bits = bytesToBitString(data.slice(offset))
  let metaSizeLength = 0
  while (metaSizeLength < bits.length && bits[metaSizeLength] === "1") {
    metaSizeLength += 1
  }
  if (metaSizeLength >= bits.length) {
    throw new RangeError("unterminated META-SIZE")
  }
  const sizeFieldLength = metaSizeLength
  const start = metaSizeLength + 1
  const sizeBits = bits.slice(start, start + sizeFieldLength)
  if (sizeBits.length !== sizeFieldLength) {
    throw new RangeError("incomplete SIZE field")
  }
  const idBytes = parseInt(sizeBits || "0", 2)
  const headerBitLength = 1 + metaSizeLength + sizeFieldLength
  const totalBitLength = headerBitLength + idBytes * 8
  if (totalBitLength > bits.length) {
    throw new RangeError("incomplete I-TAG payload")
  }
  const idBits = bits.slice(headerBitLength, totalBitLength)
  const idValue = idBits.length === 0 ? 0n : BigInt(`0b${idBits}`)
  return {
    value: idValue,
    bytesRead: Math.ceil(totalBitLength / 8),
  }
}

function encodeUint32(value: number): Uint8Array {
  const bytes = new Uint8Array(4)
  const view = new DataView(bytes.buffer)
  view.setUint32(0, value)
  return bytes
}

function decodeUint32(data: Uint8Array, offset: number): number {
  const view = new DataView(data.buffer, data.byteOffset + offset, 4)
  return view.getUint32(0)
}

/**
 * RFC 2795 section 3 IMPS packet encoding.
 */
export function encodeImpsPacket(packet: Omit<ImpsPacket, "size">): Uint8Array {
  const source = encodeITag(packet.source)
  const destination = encodeITag(packet.destination)
  const header = new Uint8Array(16)
  header.set(encodeUint32(packet.version), 0)
  header.set(encodeUint32(packet.sequenceNumber), 4)
  header.set(encodeUint32(packet.protocolNumber), 8)
  header.set(encodeUint32(packet.reserved), 12)
  const payloadWithoutSize = new Uint8Array(header.length + source.length + destination.length + packet.data.length)
  payloadWithoutSize.set(header, 0)
  payloadWithoutSize.set(source, header.length)
  payloadWithoutSize.set(destination, header.length + source.length)
  payloadWithoutSize.set(packet.data, header.length + source.length + destination.length)
  let totalSize = payloadWithoutSize.length
  while (true) {
    const sizeField = encodeITag(BigInt(totalSize))
    const nextSize = sizeField.length + payloadWithoutSize.length
    if (nextSize == totalSize) {
      const total = new Uint8Array(nextSize)
      total.set(sizeField, 0)
      total.set(payloadWithoutSize, sizeField.length)
      return total
    }
    totalSize = nextSize
  }
}

/**
 * RFC 2795 section 3 IMPS packet decoding.
 */
export function decodeImpsPacket(data: Uint8Array): ImpsPacket {
  const sizeTag = decodeITag(data, 0)
  const start = sizeTag.bytesRead
  const version = decodeUint32(data, start)
  const sequenceNumber = decodeUint32(data, start + 4)
  const protocolNumber = decodeUint32(data, start + 8)
  const reserved = decodeUint32(data, start + 12)
  const sourceTag = decodeITag(data, start + 16)
  const destinationTag = decodeITag(data, start + 16 + sourceTag.bytesRead)
  const dataStart = start + 16 + sourceTag.bytesRead + destinationTag.bytesRead
  const payload = data.slice(dataStart, Number(sizeTag.value) + start)
  return {
    version,
    sequenceNumber,
    protocolNumber,
    reserved,
    size: Number(sizeTag.value),
    source: sourceTag.value,
    destination: destinationTag.value,
    data: payload,
  }
}

interface KeeperMessage {
  version: number
  type: 0 | 1
  messageId: number
  messageCode: number
}

/**
 * RFC 2795 section 5 KEEPER payload encoding.
 */
export function encodeKeeperMessage(message: KeeperMessage): Uint8Array {
  const bytes = new Uint8Array(8)
  const view = new DataView(bytes.buffer)
  view.setUint16(0, message.version)
  view.setUint16(2, message.type)
  view.setUint16(4, message.messageId)
  view.setUint16(6, message.messageCode)
  return bytes
}

/**
 * RFC 2795 section 5 KEEPER payload decoding.
 */
export function decodeKeeperMessage(bytes: Uint8Array): KeeperMessage {
  if (bytes.length < 8) {
    throw new RangeError("KEEPER message requires 8 bytes")
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, 8)
  return {
    version: view.getUint16(0),
    type: view.getUint16(2) as 0 | 1,
    messageId: view.getUint16(4),
    messageCode: view.getUint16(6),
  }
}

/**
 * RFC 2795 section 5.3 KEEPER response requirements.
 */
export function validKeeperResponsesFor(requestCode: number): Array<number> {
  switch (requestCode) {
    case REQUEST_STATUS:
      return [
        RESPONSE_ALIVE,
        RESPONSE_DEAD,
        RESPONSE_ASLEEP,
        RESPONSE_GONE,
        RESPONSE_DISTRACTED,
        RESPONSE_NORESPONSE,
      ]
    case REQUEST_HEARTBEAT:
      return [RESPONSE_ALIVE, RESPONSE_DEAD]
    case REQUEST_STOP:
      return [RESPONSE_NORESPONSE, RESPONSE_ALIVE, RESPONSE_DEAD, RESPONSE_GONE]
    case REQUEST_TYPE:
    case REQUEST_FASTER:
      return [
        RESPONSE_ACCEPT,
        RESPONSE_REFUSE,
        RESPONSE_ASLEEP,
        RESPONSE_GONE,
        RESPONSE_NORESPONSE,
        RESPONSE_DEAD,
      ]
    case REQUEST_WAKEUP:
      return [
        RESPONSE_ACCEPT,
        RESPONSE_REFUSE,
        RESPONSE_GONE,
        RESPONSE_NORESPONSE,
        RESPONSE_DEAD,
      ]
    case REQUEST_TRANSCRIPT:
      return [RESPONSE_ACCEPT]
    default:
      return []
  }
}

/**
 * RFC 2795 section 5.4 example ZOO-to-SIMIAN exchanges using KEEPER.
 */
const keeperExchangeExample = [
  { from: "SanDiego", command: "STATUS", response: "ALIVE" },
  { from: "SanDiego", command: "WAKEUP", response: "ACCEPT" },
  { from: "SanDiego", command: "TRANSCRIPT", response: "ACCEPT" },
]

type ChimpClientCommand =
  | { kind: "SEND"; resource: string }
  | { kind: "REPLACE"; item: string }
  | { kind: "CLEAN"; item: string }
  | { kind: "NOTIFY"; status: string }
  | { kind: "TRANSCRIPT"; size: number }
  | { kind: "BYE" }

type ChimpServerCommand =
  | { kind: "HELO"; text: string }
  | { kind: "ACCEPT" }
  | { kind: "DELAY" }
  | { kind: "REFUSE" }
  | { kind: "RECEIVED" }

type ChimpCommand = ChimpClientCommand | ChimpServerCommand

/**
 * RFC 2795 sections 6.1 and 6.2 CHIMP command encoding.
 */
export function encodeChimpCommand(command: ChimpCommand): string {
  switch (command.kind) {
    case "SEND":
      return `SEND ${command.resource}`
    case "REPLACE":
      return `REPLACE ${command.item}`
    case "CLEAN":
      return `CLEAN ${command.item}`
    case "NOTIFY":
      return `NOTIFY ${command.status}`
    case "TRANSCRIPT":
      return `TRANSCRIPT ${command.size}`
    case "BYE":
      return "BYE"
    case "HELO":
      return `HELO ${command.text}`
    case "ACCEPT":
    case "DELAY":
    case "REFUSE":
    case "RECEIVED":
      return command.kind
  }
}

/**
 * RFC 2795 sections 6.1 and 6.2 CHIMP command parsing.
 */
export function parseChimpCommand(line: string): ChimpCommand {
  const trimmed = line.trim()
  if (trimmed === "BYE" || trimmed === "ACCEPT" || trimmed === "DELAY" || trimmed === "REFUSE" || trimmed === "RECEIVED") {
    return { kind: trimmed }
  }
  if (trimmed.startsWith("HELO ")) {
    return { kind: "HELO", text: trimmed.slice(5) }
  }
  if (trimmed.startsWith("SEND ")) {
    return { kind: "SEND", resource: trimmed.slice(5) }
  }
  if (trimmed.startsWith("REPLACE ")) {
    return { kind: "REPLACE", item: trimmed.slice(8) }
  }
  if (trimmed.startsWith("CLEAN ")) {
    return { kind: "CLEAN", item: trimmed.slice(6) }
  }
  if (trimmed.startsWith("NOTIFY ")) {
    return { kind: "NOTIFY", status: trimmed.slice(7) }
  }
  if (trimmed.startsWith("TRANSCRIPT ")) {
    return { kind: "TRANSCRIPT", size: Number.parseInt(trimmed.slice(11), 10) }
  }
  throw new RangeError(`unsupported CHIMP command: ${line}`)
}

/**
 * RFC 2795 section 6.3 example SIMIAN-to-ZOO session using CHIMP.
 */
const chimpSessionExample = [
  "HELO CHIMP version 1.0 4/1/2000",
  "REPLACE PAPER",
  "ACCEPT",
  "TRANSCRIPT 87",
  "ACCEPT",
  "RECEIVED",
  "SEND FOOD",
  "ACCEPT",
  "SEND MEDICINE",
  "DELAY",
  "SEND VETERINARIAN",
  "REFUSE",
  "NOTIFY NORESPONSE",
  "ACCEPT",
  "NOTIFY DEAD",
  "ACCEPT",
  "REPLACE MONKEY",
  "ACCEPT",
]

type IambPentCommand =
  | { kind: "RECEIVETH"; name: string }
  | { kind: "ANON"; size: number }
  | { kind: "ABORTETH"; text: string }
  | { kind: "HARK"; text: string }
  | { kind: "PRITHEE"; text: string }
  | { kind: "REGRETTETH"; text: string }
  | { kind: "ACCEPTETH"; text: string }

/**
 * RFC 2795 sections 7.1 and 7.2 IAMB-PENT command encoding.
 */
export function encodeIambPentCommand(command: IambPentCommand): string {
  switch (command.kind) {
    case "ANON":
      return `ANON ${command.size}`
    case "RECEIVETH":
      return `RECEIVETH ${command.name}`
    default:
      return `${command.kind} ${command.text}`.trim()
  }
}

/**
 * RFC 2795 sections 7.1 and 7.2 IAMB-PENT command parsing.
 */
export function parseIambPentCommand(line: string): IambPentCommand {
  const trimmed = line.trim()
  if (trimmed.startsWith("RECEIVETH ")) {
    return { kind: "RECEIVETH", name: trimmed.slice(10) }
  }
  if (trimmed.startsWith("ANON ")) {
    return { kind: "ANON", size: Number.parseInt(trimmed.slice(5), 10) }
  }
  for (const kind of ["ABORTETH", "HARK", "PRITHEE", "REGRETTETH", "ACCEPTETH"] as const) {
    if (trimmed.startsWith(`${kind} `)) {
      return { kind, text: trimmed.slice(kind.length + 1) }
    }
  }
  throw new RangeError(`unsupported IAMB-PENT command: ${line}`)
}

/**
 * RFC 2795 section 7.3 example ZOO-to-BARD session using IAMB-PENT.
 */
const iambPentSessionExample = [
  "HARK now, what light through yonder window breaks?",
  "RECEIVETH TRANSCRIPT SanDiego.BoBo.17",
  "PRITHEE thy monkey's wisdom poureth forth!",
  "ANON 96",
  "REGRETTETH none hath writ thy words before",
  "ABORTETH Fate may one day bless my zone",
]

type PanCommand =
  | { kind: "COMPLIMENT"; text: string }
  | { kind: "TRANSCRIPT"; name: string; size: number }
  | { kind: "THANKS" }
  | { kind: "SIGH"; insult: string }
  | { kind: "IMPRESS_ME" }
  | { kind: "REJECT"; code: number; text?: string }
  | { kind: "DONT_CALL_US_WE'LL_CALL_YOU" }

/**
 * RFC 2795 section 8.3 CRITIC reject codes.
 */
export const criticRejectCodes = new Map<number, string>([
  [0, "<Encrypted response following; see below>"],
  [1, "You're reinventing the wheel."],
  [2, "This will never, ever sell."],
  [3, "Huh?  I don't understand this at all."],
  [4, "You forgot one little obscure reference from twenty years ago that renders your whole idea null and void."],
  [5, "Due to the number of submissions, we could not accept every transcript."],
  [6, "There aren't enough charts and graphs.  Where is the color?"],
  [7, "I'm cranky and decided to take it out on you."],
  [8, "This is not in within the scope of what we are looking for."],
  [9, "This is too derivative."],
  [10, "Your submission was received after the deadline.  Try again next year."],
])

/**
 * RFC 2795 sections 8.1 and 8.2 PAN command encoding.
 */
export function encodePanCommand(command: PanCommand): string {
  switch (command.kind) {
    case "COMPLIMENT":
      return `COMPLIMENT ${command.text}`
    case "TRANSCRIPT":
      return `TRANSCRIPT ${command.name} ${command.size}`
    case "THANKS":
    case "IMPRESS_ME":
    case "DONT_CALL_US_WE'LL_CALL_YOU":
      return command.kind
    case "SIGH":
      return `SIGH ${command.insult}`.trim()
    case "REJECT":
      return command.text == null
        ? `REJECT ${command.code}`
        : `REJECT ${command.code} ${command.text}`
  }
}

/**
 * RFC 2795 sections 8.1 and 8.2 PAN command parsing.
 */
export function parsePanCommand(line: string): PanCommand {
  const trimmed = line.trim()
  if (trimmed === "THANKS" || trimmed === "IMPRESS_ME" || trimmed === "DONT_CALL_US_WE'LL_CALL_YOU") {
    return { kind: trimmed }
  }
  if (trimmed.startsWith("COMPLIMENT ")) {
    return { kind: "COMPLIMENT", text: trimmed.slice(11) }
  }
  if (trimmed.startsWith("SIGH ")) {
    return { kind: "SIGH", insult: trimmed.slice(5) }
  }
  if (trimmed.startsWith("TRANSCRIPT ")) {
    const rest = trimmed.slice(11)
    const parts = rest.split(" ")
    const size = Number.parseInt(parts.pop()!, 10)
    return { kind: "TRANSCRIPT", name: parts.join(" "), size }
  }
  if (trimmed.startsWith("REJECT ")) {
    const rest = trimmed.slice(7)
    const [codeText, ...restWords] = rest.split(" ")
    const code = Number.parseInt(codeText, 10)
    const text = restWords.length > 0 ? restWords.join(" ") : undefined
    return { kind: "REJECT", code, text }
  }
  throw new RangeError(`unsupported PAN command: ${line}`)
}

/**
 * RFC 2795 section 8.4 example ZOO-to-CRITIC session using PAN.
 */
const panSessionExample = [
  "SIGH Abandon hope all who enter here",
  "COMPLIMENT We love your work.  Your words are like",
  "COMPLIMENT jewels and you are always correct.",
  "TRANSCRIPT RomeoAndJuliet.BoBo.763 251",
  "IMPRESS_ME",
  "REJECT 2 This will never, ever sell.",
  "THANKS",
  "DONT_CALL_US_WE'LL_CALL_YOU",
]
