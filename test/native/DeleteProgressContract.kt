package com.KoreAppsTek.PhoneStorageCleaner

/** JVM-only evidence/protocol regression tests. Does not simulate Android's
 * permission manager or claim to execute real DocumentsProvider deletion. */
fun main() {
    var checks = 0
    fun verify(condition: Boolean) { check(condition); checks++ }
    val events = mutableListOf<Map<String, Any?>>()
    val ledger = DeleteProgressLedger("one", listOf("saf", "media", "failed", "absent"), events::add)
    ledger.update("awaitingPermission")
    verify(events.last()["processed"] == 0)
    verify((events.last()["confirmedBytesByUri"] as Map<*, *>).isEmpty())
    ledger.settle("saf", "deleted", 35)
    verify(events.last()["processed"] == 1)
    verify(ledger.byteSizes() == mapOf("saf" to 35L))
    ledger.update("awaitingConfirmation")
    verify(events.last()["processed"] == 1)
    verify(ledger.byteSizes() == mapOf("saf" to 35L))
    ledger.update("verifying", "media")
    verify(events.last()["currentUri"] == "media")
    ledger.settle("media", "deleted", null) // confirmed removal, unknown size
    verify(events.last()["processed"] == 2)
    verify(ledger.byteSizes() == mapOf("saf" to 35L))
    ledger.settle("failed", "failed", 999)
    ledger.settle("absent", "skipped", 999)
    verify(events.last()["processed"] == 4)
    verify(ledger.skipped() == listOf("absent"))
    verify(ledger.byteSizes().values.sum() == 35L)
    val count = events.size
    ledger.settle("saf", "deleted", 999)
    ledger.settle("saf", "failed")
    ledger.settle("foreign", "deleted", 999)
    ledger.settle("media", "unconfirmed", 999)
    verify(events.size == count)
    ledger.finish(false)
    verify(events.last()["terminal"] == true)
    val terminalCount = events.size
    ledger.finish(true)
    ledger.update("deleting", "media")
    ledger.settle("media", "deleted", 100)
    verify(events.size == terminalCount)
    val sequences = events.map { it["sequence"] as Long }
    verify(sequences.zipWithNext().all { (a,b) -> b > a })

    val cancelled = DeleteProgressLedger("cancelled", listOf("saf", "media"), events::add)
    cancelled.settle("saf", "deleted", 50)
    cancelled.update("awaitingConfirmation")
    cancelled.finish(true)
    verify(events.last()["phase"] == "cancelled")
    verify(events.last()["processed"] == 1) // untouched MediaStore item not processed
    verify(cancelled.byteSizes().values.sum() == 50L)
    verify((events.last()["outcomes"] as Map<*, *>)["media"] == null)

    // Consent alone, no cursor, a permission exception/null query, or a file
    // that was already absent are not newly reclaimed space.
    for (before in listOf<Boolean?>(true, false, null)) {
        for (after in listOf<Boolean?>(true, false, null)) {
            val expected = if (before == false) "skipped"
                else if (before == true && after == false) "deleted" else "failed"
            verify(DeleteProgressLedger.afterConfirmation(before, after) == expected)
        }
    }
    verify(DeleteProgressLedger.directRows(0) == "skipped")
    verify(DeleteProgressLedger.directRows(1) == "deleted")
    verify(DeleteProgressLedger.directRows(2) == "deleted")
    val negative = DeleteProgressLedger("sizes", listOf("one"), events::add)
    negative.settle("one", "deleted", -1)
    verify(negative.byteSizes().isEmpty())
    val legacy = DeleteProgressLedger(null, listOf("one"), events::add)
    val beforeLegacy = events.size
    legacy.settle("one", "deleted", 5)
    legacy.finish(false)
    verify(events.size == beforeLegacy)
    verify(legacy.byteSizes() == mapOf("one" to 5L))
    val codes = (1..1000).map { DeleteProgressLedger.nextRequestCode() }
    verify(codes.distinct().size == 1000)
    verify(codes.all { it in 0..65535 })
    println("Native delete progress contract: $checks assertions passed")
}
