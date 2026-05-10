import Foundation
import CoreBluetooth

/// JBD / Xiaoxiang BMS protocol over BLE.
///
/// Frame layout (request):
///   DD A5 [cmd] 00 [chk_hi chk_lo] 77
/// Frame layout (response):
///   DD [cmd] [status] [len] [payload...] [chk_hi chk_lo] 77
///
/// Checksum = 0x10000 - sum(cmd, len, payload), as a big-endian uint16.
enum JBDProtocol {
    static let serviceUUID = CBUUID(string: "FF00")
    static let notifyCharacteristicUUID = CBUUID(string: "FF01")
    static let writeCharacteristicUUID = CBUUID(string: "FF02")

    static let basicInfoCommand: Data = Data([0xDD, 0xA5, 0x03, 0x00, 0xFF, 0xFD, 0x77])
    static let cellVoltagesCommand: Data = Data([0xDD, 0xA5, 0x04, 0x00, 0xFF, 0xFC, 0x77])

    enum DecodeError: Error {
        case truncated
        case badStartByte
        case badEndByte
        case badChecksum
        case statusError(UInt8)
        case unsupportedCommand(UInt8)
    }

    struct BasicInfo {
        var totalVoltage: Double      // V
        var current: Double           // A (positive = charge)
        var remainingCapacityAh: Double
        var nominalCapacityAh: Double
        var cycleCount: Int
        var stateOfCharge: Double     // %
        var chargeFETOn: Bool
        var dischargeFETOn: Bool
        var cellCount: Int
        var temperaturesC: [Double]
    }

    /// Validate a complete response frame and return its payload bytes.
    static func payload(of frame: Data) throws -> (command: UInt8, payload: Data) {
        guard frame.count >= 7 else { throw DecodeError.truncated }
        guard frame.first == 0xDD else { throw DecodeError.badStartByte }
        guard frame.last == 0x77 else { throw DecodeError.badEndByte }

        let cmd = frame[frame.startIndex + 1]
        let status = frame[frame.startIndex + 2]
        let len = Int(frame[frame.startIndex + 3])

        guard frame.count == 7 + len else { throw DecodeError.truncated }
        if status != 0x00 { throw DecodeError.statusError(status) }

        let payloadStart = frame.startIndex + 4
        let payloadEnd = payloadStart + len
        let payload = frame[payloadStart..<payloadEnd]

        let checksumHi = frame[payloadEnd]
        let checksumLo = frame[payloadEnd + 1]
        let received = (UInt16(checksumHi) << 8) | UInt16(checksumLo)

        // Checksum is over [status, len, payload...]
        var sum: UInt32 = UInt32(status) + UInt32(len)
        for byte in payload { sum &+= UInt32(byte) }
        let expected = UInt16((0x10000 &- sum) & 0xFFFF)
        guard expected == received else { throw DecodeError.badChecksum }

        return (cmd, Data(payload))
    }

    static func decodeBasicInfo(payload p: Data) throws -> BasicInfo {
        guard p.count >= 23 else { throw DecodeError.truncated }
        let bytes = Array(p)

        func u16(_ offset: Int) -> UInt16 {
            (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
        }
        func i16(_ offset: Int) -> Int16 {
            Int16(bitPattern: u16(offset))
        }

        let voltageRaw = u16(0)                  // 10mV units
        let currentRaw = i16(2)                  // 10mA units, signed
        let remainingRaw = u16(4)                // 10mAh units
        let nominalRaw = u16(6)                  // 10mAh units
        let cycles = u16(8)
        let soc = bytes[19]
        let fet = bytes[20]
        let cellCount = Int(bytes[21])
        let ntcCount = Int(bytes[22])

        var temps: [Double] = []
        var idx = 23
        for _ in 0..<ntcCount {
            guard idx + 1 < bytes.count else { break }
            let raw = u16(idx)
            // Kelvin × 10
            let celsius = (Double(raw) - 2731.0) / 10.0
            temps.append(celsius)
            idx += 2
        }

        return BasicInfo(
            totalVoltage: Double(voltageRaw) / 100.0,
            current: Double(currentRaw) / 100.0,
            remainingCapacityAh: Double(remainingRaw) / 100.0,
            nominalCapacityAh: Double(nominalRaw) / 100.0,
            cycleCount: Int(cycles),
            stateOfCharge: Double(soc),
            chargeFETOn: (fet & 0x01) != 0,
            dischargeFETOn: (fet & 0x02) != 0,
            cellCount: cellCount,
            temperaturesC: temps
        )
    }
}

/// Reassembles BLE notifications into complete JBD frames.
/// JBD responses can arrive split across multiple ATT notifications.
final class JBDFrameAssembler {
    private var buffer = Data()

    func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        return drainCompleteFrames()
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    private func drainCompleteFrames() -> [Data] {
        var out: [Data] = []
        while true {
            // Skip until start byte.
            if let start = buffer.firstIndex(of: 0xDD), start > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<start)
            }
            guard buffer.count >= 4, buffer.first == 0xDD else { break }

            let len = Int(buffer[buffer.startIndex + 3])
            let total = 7 + len
            guard buffer.count >= total else { break }

            let frame = buffer.prefix(total)
            buffer.removeFirst(total)

            if frame.last == 0x77 {
                out.append(Data(frame))
            }
            // Otherwise drop and continue.
        }
        return out
    }
}
