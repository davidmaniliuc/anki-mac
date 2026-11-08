import CAnkiBridge
import Foundation
import SwiftProtobuf

public struct AnkiError: Error, CustomStringConvertible {
    /// Set when the backend returned a structured error; nil for bridge-level
    /// failures such as a panic or a bad init message.
    public let backend: Anki_Backend_BackendError?
    public let message: String

    public var description: String { message }
}

/// Handle to Anki's Rust backend. One per app. The backend is internally
/// synchronized, so methods may be called from any thread, but they block:
/// call them off the main actor (see `perform`).
///
/// Every RPC from anki/proto is available as a method, generated into
/// Generated/BackendServices.swift.
public final class AnkiBackend: @unchecked Sendable {
    private let handle: OpaquePointer

    public init(preferredLanguages: [String] = Locale.preferredLanguages) throws {
        var initMessage = Anki_Backend_BackendInit()
        initMessage.preferredLangs = preferredLanguages
        let bytes: Data = try initMessage.serializedBytes()
        var error = AnkiBuffer()
        let handle = bytes.withUnsafeBytes { raw in
            anki_open_backend(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count, &error)
        }
        guard let handle else {
            throw AnkiError(backend: nil, message: String(decoding: Self.take(error), as: UTF8.self))
        }
        self.handle = handle
    }

    deinit {
        anki_close_backend(handle)
    }

    /// Runs blocking backend work on a background thread.
    public func perform<T: Sendable>(_ work: @escaping @Sendable (AnkiBackend) throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work(self) }.value
    }

    /// Raw SQL against the open collection, using the JSON protocol of
    /// pylib's DBProxy.
    public func dbCommand(_ json: Data) throws -> Data {
        try call(input: json) { input, out in
            anki_run_db_command(handle, input.baseAddress, input.count, out)
        }
    }

    func run(service: UInt32, method: UInt32, input: some SwiftProtobuf.Message) throws -> Data {
        try call(input: try input.serializedBytes()) { bytes, out in
            anki_run_method(handle, service, method, bytes.baseAddress, bytes.count, out)
        }
    }

    private func call(
        input: Data,
        _ body: (UnsafeBufferPointer<UInt8>, UnsafeMutablePointer<AnkiBuffer>) -> Bool
    ) throws -> Data {
        var out = AnkiBuffer()
        let ok = input.withUnsafeBytes { raw in
            body(raw.bindMemory(to: UInt8.self), &out)
        }
        let bytes = Self.take(out)
        if ok { return bytes }
        if let error = try? Anki_Backend_BackendError(serializedBytes: bytes), !error.message.isEmpty {
            throw AnkiError(backend: error, message: error.message)
        }
        throw AnkiError(backend: nil, message: String(decoding: bytes, as: UTF8.self))
    }

    /// Copies a Rust-owned buffer into Swift and frees it.
    private static func take(_ buffer: AnkiBuffer) -> Data {
        defer { anki_free_buffer(buffer) }
        guard let ptr = buffer.ptr, buffer.len > 0 else { return Data() }
        return Data(bytes: ptr, count: buffer.len)
    }
}
