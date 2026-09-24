import {
  minutesFromApc,
  normalizeStatus,
  numberFromApc,
  type UpsTelemetry,
} from '../../domain/ups'

export function parseApcAccess(raw: string, now = Date.now()): UpsTelemetry {
  const fields: Record<string, string> = {}
  for (const line of raw.split(/\r?\n/)) {
    const index = line.indexOf(':')
    if (index > 0)
      fields[line.slice(0, index).trim()] = line.slice(index + 1).trim()
  }
  const rawStatus = fields.STATUS ?? 'UNKNOWN'
  return {
    timestamp: now,
    model: fields.MODEL ?? fields.UPSNAME ?? 'Unknown APC UPS',
    serial: fields.SERIALNO ?? null,
    firmware: fields.FIRMWARE ?? null,
    status: normalizeStatus(rawStatus),
    rawStatus,
    lineVoltage: numberFromApc(fields.LINEV),
    loadPercent: numberFromApc(fields.LOADPCT),
    batteryPercent: numberFromApc(fields.BCHARGE),
    runtimeMinutes: minutesFromApc(fields.TIMELEFT),
    batteryVoltage: numberFromApc(fields.BATTV),
    nominalPowerWatts: numberFromApc(fields.NOMPOWER),
    nominalBatteryVoltage: numberFromApc(fields.NOMBATTV),
    transfers: numberFromApc(fields.NUMXFR),
    lastTransfer: fields.LASTXFER ?? null,
    onBatterySeconds: numberFromApc(fields.TONBATT),
    batteryDate: fields.BATTDATE ?? null,
    selfTest: fields.SELFTEST ?? null,
    sensitivity: fields.SENSE ?? null,
    lowTransferVoltage: numberFromApc(fields.LOTRANS),
    highTransferVoltage: numberFromApc(fields.HITRANS),
    stale: false,
    source: 'apcupsd',
    capabilities: [],
    capabilityReason:
      'Automated maintenance has not been proven safe without the system agent capability report.',
    maintenance: null,
  }
}

export function offlineTelemetry(
  now = Date.now(),
  message = 'COMMLOST',
): UpsTelemetry {
  return {
    timestamp: now,
    model: 'APC UPS',
    serial: null,
    firmware: null,
    status: 'offline',
    rawStatus: message,
    lineVoltage: null,
    loadPercent: null,
    batteryPercent: null,
    runtimeMinutes: null,
    batteryVoltage: null,
    nominalPowerWatts: null,
    nominalBatteryVoltage: null,
    transfers: null,
    lastTransfer: null,
    onBatterySeconds: null,
    batteryDate: null,
    selfTest: null,
    sensitivity: null,
    lowTransferVoltage: null,
    highTransferVoltage: null,
    stale: true,
    source: 'apcupsd',
    capabilities: [],
    capabilityReason:
      'Maintenance is unavailable while UPS communication is offline.',
    maintenance: null,
  }
}
