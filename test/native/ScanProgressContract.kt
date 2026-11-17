package com.KoreAppsTek.PhoneStorageCleaner

import java.util.concurrent.CancellationException

/** Standalone JVM contract tests; no Android device or Gradle test dependency.
 * Compile this file with ScanProgressBridge.kt and its Android/Flutter API jars.
 * The injected clock/post queue avoids calling Android runtime stub methods.
 */
fun main() {
    var checks = 0
    fun verify(condition: Boolean) { check(condition); checks++ }
    val queue = ArrayDeque<() -> Unit>()
    val events = mutableListOf<Map<String, Any?>>()
    var now = 1000L
    var releases = 0
    fun request(id: String? = "one") = NativeScanProgress(
        id, { queue.add(it) }, { events.add(it) }, { releases++ }, { now },
    )
    fun flush() { while (queue.isNotEmpty()) queue.removeFirst().invoke() }

    val measured = request()
    measured.numeric = true
    measured.update("Reading images", 0, 1000, force = true)
    flush()
    verify(events.last()["processed"] == 0)
    verify(events.last()["total"] == 1000)
    verify(events.last()["numeric"] == true)
    for (done in listOf(100, 250, 500, 750)) {
        now += 80
        measured.update("Reading images", done, 1000)
        flush()
        verify(events.last()["processed"] == done)
        verify(events.last()["total"] == 1000)
    }
    // Coalesce a busy worker's notifications: at most one pending runnable.
    repeat(100) {
        now += 80
        measured.update("Reading images", 751 + it, 1000)
    }
    verify(queue.size == 1)
    measured.finish()
    verify(queue.size == 1)
    flush()
    verify(events.last()["outcome"] == "succeeded")
    verify(releases == 1)
    val preserved = mapOf("files" to listOf("unchanged"))
    val envelope = measured.wrap(preserved) as Map<*, *>
    verify(envelope["scanPayload"] === preserved)

    val unknown = request("folders")
    now += 80
    unknown.update("Discovering folders", 250)
    flush()
    verify(events.last()["total"] == null)
    verify(events.last()["numeric"] == false)
    unknown.incomplete()
    unknown.finish()
    flush()
    verify(events.last()["outcome"] == "partial")
    verify((unknown.wrap(preserved) as Map<*, *>)["scanOutcome"] == "partial")

    val failed = request("failed")
    failed.finish("failed")
    flush()
    verify(events.last()["outcome"] == "failed")

    val cancelled = request("cancelled")
    cancelled.cancel()
    var caught = false
    try { cancelled.check() } catch (_: CancellationException) { caught = true }
    verify(caught)
    cancelled.finish()
    flush()
    verify(events.last()["outcome"] == "cancelled")
    verify((cancelled.wrap(preserved) as Map<*, *>)["scanOutcome"] == "cancelled")

    // A native request can have many real worklists. Preserve the last exact
    // count before a boundary even when 80ms sampling suppressed that count.
    val staged = request("staged")
    staged.update("Hashing", 0, 4, force = true)
    flush()
    val firstIndex = events.last()["stageIndex"] as Int
    val firstSequence = events.last()["sequence"] as Long
    staged.update("Hashing", 4, 4) // same clock tick, normally throttled
    staged.update("Fingerprinting", 0, 8)
    verify(queue.size == 1)
    flush()
    val firstStage = events.filter { it["requestId"] == "staged" && it["stageIndex"] == firstIndex }
    verify(firstStage.last()["processed"] == 4)
    verify(firstStage.last()["total"] == 4)
    verify(firstStage.last()["outcome"] == "stageComplete")
    verify((firstStage.last()["sequence"] as Long) > firstSequence)
    verify(events.last()["stage"] == "Fingerprinting")
    verify(events.last()["processed"] == 0)
    verify((events.last()["stageIndex"] as Int) > firstIndex)
    val secondIndex = events.last()["stageIndex"]
    staged.update("Fingerprinting", 4, 8, force = true)
    staged.update("Fingerprinting", 0, 8) // repeated name, new worklist
    flush()
    verify(events.last()["stageIndex"] != secondIndex)
    staged.update("Fingerprinting", 8, 8)
    staged.finish()
    val stagedEnvelope = staged.wrap(preserved) as Map<*, *>
    val finalStage = stagedEnvelope["scanStage"] as Map<*, *>
    verify(finalStage["processed"] == 8)
    verify(finalStage["outcome"] == "succeeded")
    flush()
    verify(events.last() == finalStage)
    val terminalCount = events.size
    staged.update("Late callback", 0, 100, force = true)
    staged.finish("failed")
    flush()
    verify(events.size == terminalCount)
    verify((staged.wrap(preserved) as Map<*, *>)["scanOutcome"] == "succeeded")

    // A fast multi-stage request cannot create an unbounded main-thread queue.
    val fast = request("fast")
    repeat(100) { fast.update("Stage $it", 0, 1) }
    verify(queue.size == 1)
    val beforeFast = events.size
    fast.finish()
    flush()
    verify(events.size - beforeFast <= 16)
    verify(events.last()["stage"] == "Stage 99")

    val legacy = request(null)
    verify(legacy.wrap(preserved) === preserved)
    val before = events.size
    legacy.update("Legacy", 1, 2)
    legacy.finish()
    flush()
    verify(events.size == before)
    println("Native scan progress contract: $checks assertions passed")
}
