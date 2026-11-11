import AnkiKit
import Foundation

/// Raw protobuf RPCs exposed to trusted upstream pages: the camelCased
/// `exposed_backend_list` of mediasrv.py, with service and method ids taken from
/// the generated BackendServices.swift. Handlers mediasrv implements in Python
/// (post_handler_list) are not here; add them as native cases when a page needs one.
enum PageBackendRPC {
    /// Page-facing (camelCase) names, as upstream pages post them to /_anki/<name>.
    private static let methods: [String: (service: UInt32, method: UInt32)] = [
        "latestProgress": (3, 4),
        "getCustomColours": (3, 15),
        "getDeckNames": (7, 13),
        "getDeck": (7, 8),
        "i18nResources": (35, 2),
        "getCsvMetadata": (39, 5),
        "getImportAnkiPackagePresets": (39, 3),
        "importCsv": (39, 6),
        "importAnkiPackage": (39, 2),
        "importJsonFile": (39, 9),
        "importJsonString": (39, 10),
        "getFieldNames": (23, 16),
        "getNote": (25, 6),
        "newNote": (25, 0),
        "noteFieldsCheck": (25, 11),
        "defaultsForAdding": (25, 3),
        "defaultDeckForNotetype": (25, 4),
        "addNote": (25, 1),
        "updateNotes": (25, 5),
        "updateNotetype": (23, 1),
        "getNotetype": (23, 6),
        "getNotetypeNames": (23, 8),
        "getChangeNotetypeInfo": (23, 14),
        "getClozeFieldOrds": (23, 18),
        "cardStats": (43, 0),
        "getReviewLogs": (43, 1),
        "graphs": (43, 2),
        "getGraphPreferences": (43, 3),
        "setGraphPreferences": (43, 4),
        "completeTag": (45, 10),
        "getImageForOcclusion": (37, 0),
        "addImageOcclusionNote": (37, 4),
        "getImageOcclusionNote": (37, 1),
        "updateImageOcclusionNote": (37, 5),
        "getImageOcclusionFields": (37, 2),
        "computeFsrsParams": (13, 30),
        "computeOptimalRetention": (13, 32),
        "setWantsAbort": (3, 5),
        "evaluateParamsLegacy": (13, 36),
        "getOptimalRetentionParameters": (13, 31),
        "simulateFsrsReview": (13, 33),
        "simulateFsrsWorkload": (13, 34),
        "getIgnoredBeforeCount": (11, 8),
        "getRetentionWorkload": (11, 9),
        "encodeIriPaths": (27, 11),
        "decodeIriPaths": (27, 12),
        "htmlToTextLine": (27, 14),
        "setConfigJson": (9, 1),
        "getConfigBool": (9, 5),
        "addMediaFile": (41, 2),
        "addMediaFromPath": (41, 3),
        "addMediaFromUrl": (41, 0),
        "getAbsoluteMediaPath": (41, 9),
        "extractMediaFiles": (41, 8),
        "getCard": (5, 0),
    ]

    static func run(_ name: String, body: Data, backend: AnkiBackend) throws -> Data {
        guard let entry = methods[name] else {
            throw PageRPCError(message: "Unknown or disallowed page method: \(name)")
        }
        return try backend.runRaw(service: entry.service, method: entry.method, input: body)
    }
}

/// A page call that was refused; its message is the body of the 500 response.
struct PageRPCError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
