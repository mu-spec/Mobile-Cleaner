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

    val legacy = request(null)
    verify(legacy.wrap(preserved) === preserved)
    val before = events.size
    legacy.update("Legacy", 1, 2)
    legacy.finish()
    flush()
    verify(events.size == before)
    println("Native scan progress contract: $checks assertions passed")
}
