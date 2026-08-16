# Phase 17 — Duplicate File Detection

## Goal

Find **exact duplicates only** — byte-identical files — using the pipeline:

```
same size  →  candidate group  →  hash  →  exact duplicate
```

No AI, no perceptual matching, no similarity scoring. Two photos of the same
scene are not duplicates here, and treating them as such would risk deleting
the better shot.

## The pipeline

### Stage 1 — same size

Size comes free from the Phase 6 scan, so it eliminates almost everything
before a single byte is read. Files are grouped by exact byte size, and only
sizes shared by **two or more** files survive.

Two guards matter here:

- **De-duplicate by URI first.** A file reported under both Downloads and APKs
  would otherwise be grouped with itself and reported as its own duplicate.
- **A 16 KB floor.** Thousands of tiny system artefacts share sizes, and
  grouping them is noise rather than cleaning.

### Stage 2 — hash the candidates

Only files that survived stage 1 are read. `FileHashBridge` streams each
through a **SHA-256** digest with a 64 KB buffer — never loading the file,
since a duplicate set can include multi-gigabyte video. Hashing runs on a
background pool, capped at 400 files per call.

A file that cannot be read is **omitted from the results**, never guessed at.
An unreadable file cannot be proven identical and must not be offered for
deletion.

On the Dart side, `PlatformFileHashRepository` caches by URI, so a hash is
computed at most once per session.

### Stage 3 — group by hash

Files sharing a size *and* a hash form a `DuplicateGroup`, sorted oldest first.
Groups are ranked by the space a clean-up would actually recover.

## The safety rule

**One copy of every set is always kept.**

`DuplicateGroup.original` is the oldest copy — usually the real original rather
than a re-download or a share-sheet copy — and `duplicates` is everything else.
The UI renders the kept copy in a locked row with **no checkbox**, and
`allDuplicates` excludes it, so even Select copies cannot select it.

This is why the headline figure is `reclaimableBytes`, not `totalBytes`:
deleting every copy of a file is data loss, not cleaning. A three-copy set of
5 MB files occupies 15 MB but can only recover 10 MB.

## Screen

- Headline: recoverable total, the number of extra copies and sets, and a note
  that matching is byte for byte and one copy is always kept.
- One card per set: copy count, per-file size, the saving, the locked kept
  copy, then each removable copy as a selectable Phase 8 row.
- **Select copies** takes every removable copy across every set.
- Deletion reuses `runDeleteFlow` unchanged.
- The loading state says "Comparing files… only files of matching size are
  read", because hashing can take a moment and a bare spinner would look stuck.

## Entry points

Route `/duplicates`, reachable from the **Files** tab and the **Photos** tab,
where Duplicates is promoted from "coming soon" to a working tool.

## Automated tests

`test/duplicates_test.dart`:

**Stage 1** — only shared sizes become candidates; the floor excludes tiny
files; a unique size is never hashed; a file reported twice is not its own
duplicate.

**Stage 2** — same size but different content does **not** group; identical
content does; reclaimable space keeps one copy; groups ordered by saving; an
unhashable file is dropped rather than assumed identical; no hashes yields no
duplicates; work counters are reported.

**Safety** — the oldest copy is kept and never listed as removable; every group
excludes exactly one copy; occupied and reclaimable totals differ correctly.

**Screen** — only the seven size-matched candidates are hashed, not the whole
library; the total and counts; the kept copy has no checkbox while its copies
do; Select copies selects three, never five; the action bar appears; empty
state; a same-size-different-content library shows no duplicates.

**Payload parsing** — well-formed entries kept, malformed rows and a null
payload dropped.

## Device acceptance test

1. Put two identical copies of a photo on the device, plus two different files
   that happen to share a size.
2. Open **Files → Duplicates**.
3. Confirm the identical pair is grouped and the same-size pair is not.
4. Confirm one copy is shown as kept, with no checkbox.
5. Tap **Select copies** and confirm the count equals the extra copies only.
6. Delete, approve the Android dialog, and confirm one copy survives.

## Notes and limits

- Exact matches only. A re-encoded or resized image is not a duplicate.
- Capped at 500 files per category scanned and 400 hashed per call.
- Files under 16 KB are ignored.
- Hashing reads file contents, so a first run over a large library takes longer
  than other tools. Results are cached per session.
- The same scoped-storage limits apply as elsewhere.
