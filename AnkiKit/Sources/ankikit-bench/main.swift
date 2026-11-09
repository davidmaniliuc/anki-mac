// Times the backend calls the app makes, through the Swift bridge, on a copy
// of a bench fixture. This measures the floor the SwiftUI app sits on: no UI,
// no web view, just process start + rslib.
//
//     swift run -c release ankikit-bench <fixture dir> [runs]

import AnkiKit
import Darwin
import Foundation

let processStart: Date = {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    sysctl(&mib, 4, &info, &size, nil, 0)
    let tv = info.kp_proc.p_starttime
    return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
}()

func ms(_ start: ContinuousClock.Instant) -> Double {
    let d = ContinuousClock.now - start
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

func time<T>(_ body: () throws -> T) rethrows -> (T, Double) {
    let start = ContinuousClock.now
    let value = try body()
    return (value, ms(start))
}

func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return Double(info.phys_footprint) / 1_048_576
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: ankikit-bench <fixture dir>\n".utf8))
    exit(2)
}
let fixture = URL(fileURLWithPath: args[1])
let processStartToMain = Date().timeIntervalSince(processStart) * 1000

// Work on a clone so answering cards never touches the fixture.
let work = FileManager.default.temporaryDirectory.appendingPathComponent("ankikit-bench-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }
for name in try FileManager.default.contentsOfDirectory(atPath: fixture.path) {
    let clone = Process()
    clone.executableURL = URL(fileURLWithPath: "/bin/cp")
    clone.arguments = ["-cR", fixture.appendingPathComponent(name).path, work.path]
    try clone.run()
    clone.waitUntilExit()
}

var result: [String: Any] = [:]

result["process_start_to_main_ms"] = processStartToMain
// Excludes the fixture clone above, which the real app never does.
let backendStart = ContinuousClock.now
let (backend, initMs) = try time { try AnkiBackend() }
result["backend_init_ms"] = initMs

var open = Anki_Collection_OpenCollectionRequest()
open.collectionPath = work.appendingPathComponent("collection.anki2").path
open.mediaFolderPath = work.appendingPathComponent("collection.media").path
open.mediaDbPath = work.appendingPathComponent("collection.media.db2").path
result["open_collection_ms"] = try time { try backend.openCollection(open) }.1

var treeRequest = Anki_Decks_DeckTreeRequest()
treeRequest.now = Int64(Date().timeIntervalSince1970)
let (tree, treeMs) = try time { try backend.deckTree(treeRequest) }
result["deck_tree_ms"] = treeMs
result["process_start_to_deck_tree_ms"] = processStartToMain + ms(backendStart)

// Same deck choice as the desktop bench add-on: the top-level deck with most due.
let best = tree.children.max {
    ($0.reviewCount + $0.learnCount + $0.newCount) < ($1.reviewCount + $1.learnCount + $1.newCount)
}
if let best {
    var select = Anki_Decks_DeckId()
    select.did = best.deckID
    try backend.setCurrentDeck(select)
}

// Study: fetch, render question+answer, answer Good. 30 cards, like the desktop run.
var answerMs: [Double] = []
var fetchRequest = Anki_Scheduler_GetQueuedCardsRequest()
fetchRequest.fetchLimit = 1
let studyStart = ContinuousClock.now
var firstQuestionMs: Double?
for _ in 0..<30 {
    let start = ContinuousClock.now
    guard let queued = try backend.getQueuedCards(fetchRequest).cards.first else { break }
    var render = Anki_CardRendering_RenderExistingCardRequest()
    render.cardID = queued.card.id
    _ = try backend.renderExistingCard(render)
    if firstQuestionMs == nil { firstQuestionMs = ms(studyStart) }
    var answer = Anki_Scheduler_CardAnswer()
    answer.cardID = queued.card.id
    answer.currentState = queued.states.current
    answer.newState = queued.states.good
    answer.rating = .good
    answer.answeredAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
    answer.millisecondsTaken = 3000
    _ = try backend.answerCard(answer)
    answerMs.append(ms(start))
}
result["study_first_card_ms"] = firstQuestionMs ?? NSNull()
result["answer_to_next_card_ms"] = median(answerMs)
result["answers"] = answerMs.count

// Browser: whole-collection searches, then the visible rows of the table.
// Sorted as desktop's find_cards(order=True): the column and direction in the config.
func configJSON<T: Decodable>(_ key: String, as type: T.Type) -> T? {
    var request = Anki_Generic_String()
    request.val = key
    return (try? backend.getConfigJson(request).json).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
}
var sort = Anki_Search_SortOrder.Builtin()
sort.column = configJSON("sortType", as: String.self) ?? "noteFld"
sort.reverse = configJSON("sortBackwards", as: Bool.self) ?? false
var searchMs: [String: Double] = [:]
var lastIds: [Int64] = []
for query in ["deck:*", "is:due", "front:*a*"] {
    var request = Anki_Search_SearchRequest()
    request.search = query
    request.order.builtin = sort
    let (response, elapsed) = try time { try backend.searchCards(request) }
    searchMs[query] = elapsed
    lastIds = response.ids
}
result["search_ms"] = searchMs
result["browser_rows"] = lastIds.count
result["browser_first_screen_rows_ms"] = try time {
    // As pylib's load_browser_card_columns: stored columns, else the defaults.
    var key = Anki_Generic_String()
    key.val = "activeCols"
    var columns = Anki_Generic_StringList()
    columns.vals = (try? JSONDecoder().decode([String].self, from: backend.getConfigJson(key).json))
        ?? ["noteFld", "template", "cardDue", "deck"]
    try backend.setActiveBrowserColumns(columns)
    for id in lastIds.prefix(40) {
        var row = Anki_Generic_Int64()
        row.val = id
        _ = try backend.browserRowForId(row)
    }
}.1

var graphs = Anki_Stats_GraphsRequest()
graphs.search = "deck:*"
graphs.days = 365
result["graphs_ms"] = try time { try backend.graphs(graphs) }.1

result["footprint_mb"] = footprintMB()
result["close_collection_ms"] = try time { try backend.closeCollection(Anki_Collection_CloseCollectionRequest()) }.1

let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: json, as: UTF8.self))
