///
///  largeGunzip
///
///  Unzip large gzip file
///  Based on DataCompression(https://github.com/mw99/DataCompression) by Markus Wanke
///
///  Created by Kwonsoo Moon, 2018/02/01
///


///
///                Apache License, Version 2.0
///
///  Copyright 2016, Markus Wanke
///
///  Licensed under the Apache License, Version 2.0 (the "License");
///  you may not use this file except in compliance with the License.
///  You may obtain a copy of the License at
///
///  http://www.apache.org/licenses/LICENSE-2.0
///
///  Unless required by applicable law or agreed to in writing, software
///  distributed under the License is distributed on an "AS IS" BASIS,
///  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
///  See the License for the specific language governing permissions and
///  limitations under the License.
///


import Foundation
import Compression

public typealias GzProgressHandler = ((_: Double) -> Void)
public typealias GzCancelHandler = (() -> Bool)

public extension Data {
    
    /// Decompresses the data using the gzip deflate algorithm. Self is expected to be a gzip deflate
    /// stream according to [RFC-1952](https://tools.ietf.org/html/rfc1952).
    /// - returns: uncompressed data
    @available(iOS 9.0, *)
    public func gunzip(filePath: String, progress: GzProgressHandler? = nil, shouldCancel: GzCancelHandler? = nil) -> Bool {
        // 10 byte header + data +  8 byte footer. See https://tools.ietf.org/html/rfc1952#section-2
        let overhead = 10 + 8
        guard count >= overhead else { return false }
        
        
        typealias GZipHeader = (id1: UInt8, id2: UInt8, cm: UInt8, flg: UInt8, xfl: UInt8, os: UInt8)
        let hdr: GZipHeader = withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> GZipHeader in
            // +---+---+---+---+---+---+---+---+---+---+
            // |ID1|ID2|CM |FLG|     MTIME     |XFL|OS |
            // +---+---+---+---+---+---+---+---+---+---+
            return (id1: ptr[0], id2: ptr[1], cm: ptr[2], flg: ptr[3], xfl: ptr[8], os: ptr[9])
        }
        
        typealias GZipFooter = (crc32: UInt32, isize: UInt32)
        let ftr: GZipFooter = withUnsafeBytes { (bptr: UnsafePointer<UInt8>) -> GZipFooter in
            // +---+---+---+---+---+---+---+---+
            // |     CRC32     |     ISIZE     |
            // +---+---+---+---+---+---+---+---+
            return bptr.advanced(by: count - 8).withMemoryRebound(to: UInt32.self, capacity: 2) { ptr in
                return (ptr[0].littleEndian, ptr[1].littleEndian)
            }
        }
        
        // Wrong gzip magic or unsupported compression method
        guard hdr.id1 == 0x1f && hdr.id2 == 0x8b && hdr.cm == 0x08 else { return false }
        
        let has_crc16: Bool = hdr.flg & 0b00010 != 0
        let has_extra: Bool = hdr.flg & 0b00100 != 0
        let has_fname: Bool = hdr.flg & 0b01000 != 0
        let has_cmmnt: Bool = hdr.flg & 0b10000 != 0
        
        _ = withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Data? in
            var pos = 10 ; let limit = count - 8
            
            if has_extra {
                pos += ptr.advanced(by: pos).withMemoryRebound(to: UInt16.self, capacity: 1) {
                    return Int($0.pointee.littleEndian) + 2 // +2 for xlen
                }
            }
            if has_fname {
                while pos < limit && ptr[pos] != 0x0 { pos += 1 }
                pos += 1 // skip null byte as well
            }
            if has_cmmnt {
                while pos < limit && ptr[pos] != 0x0 { pos += 1 }
                pos += 1 // skip null byte as well
            }
            if has_crc16 {
                pos += 2 // ignoring header crc16
            }
            
            guard pos < limit else { return nil }
            let config = (operation: COMPRESSION_STREAM_DECODE, algorithm: COMPRESSION_ZLIB)
            _ = perform(config,
                        source: ptr.advanced(by: pos),
                        sourceSize: limit - pos,
                        filePath: filePath,
                        progress: progress,
                        shouldCancel: shouldCancel)
            return nil
            //return perform(config, source: ptr.advanced(by: pos), sourceSize: limit - pos, filePath: filePath)
        }
        
        
        return FileManager.default.fileExists(atPath: filePath) && ftr.isize == UInt32(truncatingIfNeeded: readFileSize(of: filePath))
        
        
        //        guard let inflated = try? Data(contentsOf: URL(fileURLWithPath: filePath), options: Data.ReadingOptions.alwaysMapped) else {
        //            return false
        //        }
        //        guard ftr.isize == UInt32(truncatingIfNeeded: inflated.count)  else { return false }
        //        guard ftr.crc32 == inflated.crc32().checksum                   else { return false }
        //        return true
    }
}

private typealias Config = (operation: compression_stream_operation, algorithm: compression_algorithm)

private func readFileSize(of path: String) -> UInt64 {
    guard let attr = try? FileManager.default.attributesOfItem(atPath: path) else {
        return 0
    }
    return (attr[FileAttributeKey.size] as? NSNumber)?.uint64Value ?? 0
}

private func appendData(_ data: Data, to fileHandle: FileHandle) {
    fileHandle.seekToEndOfFile()
    fileHandle.write(data)
}

private func createFile(at filePath: String, initialData: Data) -> FileHandle {
    
    if let existing = FileHandle(forWritingAtPath: filePath) {
        existing.seekToEndOfFile()
        existing.write(initialData)
        return existing
    } else {
        FileManager.default.createFile(atPath: filePath, contents: initialData, attributes: nil)
        return FileHandle(forWritingAtPath: filePath)!
    }
}

@available(iOS 9.0, *)
private func perform(_ config: Config,
                     source: UnsafePointer<UInt8>,
                     sourceSize: Int,
                     filePath: String,
                     progress: GzProgressHandler? = nil,
                     shouldCancel: GzCancelHandler? = nil) -> Bool {
    guard config.operation == COMPRESSION_STREAM_ENCODE || sourceSize > 0 else { return false }
    
    let streamBase = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    defer { streamBase.deallocate() }
    var stream = streamBase.pointee
    
    let status = compression_stream_init(&stream, config.operation, config.algorithm)
    guard status != COMPRESSION_STATUS_ERROR else { return false }
    defer { compression_stream_destroy(&stream) }
    
    let bufferSize = Swift.max( Swift.min(sourceSize, 64 * 1024), 64)
    //    let bufferSize = Swift.max( Swift.min(sourceSize, 1024 * 1024), 64)
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    
    stream.dst_ptr  = buffer
    stream.dst_size = bufferSize
    stream.src_ptr  = source
    stream.src_size = sourceSize
    
    let flags: Int32 = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
    var fileHandle: FileHandle?
    while true {
        switch compression_stream_process(&stream, flags) {
        case COMPRESSION_STATUS_OK:
            guard stream.dst_size == 0 else { return false }
            
            if shouldCancel?() ?? false {
                return false
            }
            
            if let handle = fileHandle {
                appendData(Data(bytes: buffer, count: stream.dst_ptr - buffer), to: handle)
            } else {
                fileHandle = createFile(at: filePath, initialData: Data(bytes: buffer, count: stream.dst_ptr - buffer))
            }
            
            progress?( Double(sourceSize - stream.src_size) / Double(sourceSize))
            stream.dst_ptr = buffer
            stream.dst_size = bufferSize
            
        case COMPRESSION_STATUS_END:
            
            if let handle = fileHandle {
                appendData(Data(bytes: buffer, count: stream.dst_ptr - buffer), to: handle)
            } else {
                fileHandle = createFile(at: filePath, initialData: Data(bytes: buffer, count: stream.dst_ptr - buffer))
            }
            
            progress?( Double(sourceSize - stream.src_size) / Double(sourceSize))
            fileHandle?.closeFile()
            return true
        default:
            fileHandle?.closeFile()
            return false
        }
    }
}
