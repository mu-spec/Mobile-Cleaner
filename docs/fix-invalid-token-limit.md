# Fix — "We could not scan your files" on Android 11+

Reported from a device running **Android 14**: the app installs and opens, but
Smart Scan immediately shows the error state.

## The screenshot was the diagnosis

Three details in it, taken together, identify the bug without logcat:

1. **The error is `We could not scan your files`, not `Storage access is
   required`.** `FilesErrorView` picks the headline by testing
   `error.toString().contains('PERMISSION')`. The scanner raises
   `SCAN_PERMISSION_DENIED` for a `SecurityException` and `SCAN_FAILED` for
   anything else. The generic headline means **the native code threw a
   non-security exception** — so this was never a permissions problem.
2. **There is no "Review permissions" button.** Same branch, confirming it.
3. **It failed instantly**, with no spinner. The throw happens on the first
   MediaStore query, before any row is read.

So: a non-security exception, thrown immediately, on a modern Android, on a
code path that works on the developer's older device.

## Root cause

`FileScannerBridge.runQuery` built its row limit into the sort-order string —
the classic MediaStore idiom:

```kotlin
val order = "${sortColumn(sortOrder)} LIMIT $limit"   // "_size DESC LIMIT 500"
resolver.query(collection, projection, selection, args, order)
```

**Android 11 (API 30) added a SQL token validator to `MediaProvider` that
rejects this.** The query throws:

```
java.lang.IllegalArgumentException: Invalid token LIMIT
```

`onMethodCall` catches it and returns `SCAN_FAILED`, which is exactly the
screen in the report.

### Why it was never seen before

The validator applies to apps **targeting** API 30+. `build.gradle.kts` uses
`targetSdk = flutter.targetSdkVersion`, which follows the Flutter SDK and is
well past 30 — so the shipped APK opts in. The failure then depends on the
*device*: fine below Android 11, broken on 11, 12, 13 and 14.

This is also why every phase of static review missed it. The code is correct
Kotlin, the API is real and not deprecated, and the string is well-formed. It
is a **runtime platform behaviour change**, invisible to compilation and to
widget tests, which stub the scanner out entirely. Only a real device on a new
Android version could surface it — which is precisely what happened.

### Blast radius

Total, on Android 11+. `runQuery` is the single funnel for every MediaStore
category — images, videos, audio, documents, downloads, APKs. So Smart Scan,
Files, Large Files, Downloads Cleaner, APK Cleaner, Screenshots, Large Photos,
Duplicates, Similar Photos and Videos were **all** broken on any modern device.
Storage info and the Apps tab do not use this path and would have kept working.

## The fix

A new `queryWithLimit` helper picks the right mechanism per API level:

- **API 30+** — the limit travels as a real query argument in a `Bundle`:
  `QUERY_ARG_LIMIT`, with `QUERY_ARG_SQL_SORT_ORDER`,
  `QUERY_ARG_SQL_SELECTION` and `QUERY_ARG_SQL_SELECTION_ARGS` alongside it.
- **Below API 30** — the legacy `"$order LIMIT $limit"` string, which is still
  the only option there.

Both branches keep the existing selection, arguments, projection and ordering,
so behaviour below Android 11 is unchanged.

This was the only occurrence in the codebase; `DeleteBridge` and
`SafDocumentScanner` pass `null` sort orders and were unaffected.

## Also changed: the error state is now diagnosable

The reason this took a user report is that the failure showed a headline and
nothing else.

- `SCAN_FAILED` now includes the exception class name, because
  `IllegalArgumentException.message` alone is easy to lose and `error.message`
  is often null.
- `FilesErrorView` renders the underlying reason under the headline
  (`files_error_detail`). The next time something breaks on a device I cannot
  test, the screenshot will carry the actual cause.

## Files changed

- `android/app/src/main/kotlin/com/mobilecleaner/app/FileScannerBridge.kt` —
  `queryWithLimit`, `Bundle` import, richer `SCAN_FAILED` detail
- `lib/features/files/presentation/widgets/files_status_views.dart` —
  error detail line

## Verification status

**Static review only** — still no Android toolchain in this workspace, so this
has not been compiled. Given that an unverified fix is what caused the problem,
please confirm on the Android 14 device before trusting it.

Worth checking specifically: that results on Android 11+ are still **capped**
at the limit and still **sorted** (biggest-first in Large Files is the quickest
tell). Some OEM providers have historically honoured `QUERY_ARG_LIMIT` while
ignoring `QUERY_ARG_SQL_SORT_ORDER`; if ordering looks wrong, the fallback is
to sort in Dart after the scan.
