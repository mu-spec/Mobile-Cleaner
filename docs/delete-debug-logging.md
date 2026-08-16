# Temporary delete diagnostics

**This commit adds logging only. No deletion behaviour was changed.**

Real devices report *"Access to this file was denied."* for every type. Static
analysis has produced two plausible causes already, so rather than guess a
third time, this instruments the shared backend and lets the device say what is
actually happening.

Remove this logging once the cause is confirmed.

## Capturing a log

```bash
adb logcat -c                      # clear
# reproduce: select an item, tap Delete, complete or cancel the dialog
adb logcat -s DELETE_DEBUG:V       # or: adb logcat | grep DELETE_DEBUG
```

Every line is prefixed `[DELETE_DEBUG]`. Stack traces are attached to the
`Log.e` calls, so use `-v long` if they are being truncated.

## What is logged

### Once per request

```
===== delete request ===== sdkInt=34 (14) | device=Google Pixel 7 | requested=3
```

Android SDK version and release, device, and how many items were sent.

### Once per item, before anything is attempted

```
plan | category=images | name=IMG_1.jpg | originalPath=/storage/... |
mimeType=image/jpeg | sizeBytes=3145728 |
uri=content://media/external/images/media/42 | scheme=content:// |
authority=media | strategy=MEDIASTORE/createDeleteRequest (API 30+) |
safPermission=none | mediaStoreLookup=ok | rows=1
```

This single line answers most of the open questions:

| Field | Tells us |
| --- | --- |
| `category` / `name` / `originalPath` | which item, and what type |
| `uri` / `scheme` / `authority` | `content://` vs `file://` vs raw path |
| `strategy` | **which branch was chosen** |
| `safPermission` | whether a persisted grant exists, and read vs write |
| `mediaStoreLookup` | whether MediaStore can still see the row |

`scheme` reports `content://`, `file://`, or `raw/<scheme>`, so a malformed URI
is obvious. `safPermission` reports `safRead` and `safWrite` separately, which
is what would confirm or rule out the read-only-grant theory.

Then a routing summary:

```
routing | saf=0 direct=0 mediaStore=3
```

If media items are being counted under `saf`, that confirms the misrouting
theory instead.

### Per attempt, with the raw API result

```
SAF attempt | ... | safPermission=yes | safRead=true | safWrite=false
SAF result | deleteDocument returned=false | uri=...
DIRECT probe | path=/storage/... | exists=true | canRead=true | canWrite=false
DIRECT result | File.delete returned=false | path=...
MEDIASTORE attempt | ... | mediaStoreLookup=ok | rows=1
MEDIASTORE result | resolver.delete rows=0 | uri=...
```

The exact return value of `DocumentsContract.deleteDocument`,
`File.delete()`, and `ContentResolver.delete` is logged, so a silent `false`
or `0` is distinguishable from a thrown exception.

### Every exception, in full

```
[DELETE_DEBUG] SAF SecurityException | uri=... |
exceptionClass=java.lang.SecurityException |
exceptionMessage=Permission Denial: ...
    <full stack trace>
```

Class, message and stack trace are logged separately so a truncated logcat
line still identifies the exception.

### System dialog and outcome

```
MEDIASTORE bulk | createDeleteRequest for 3 uri(s)
MEDIASTORE bulk | system dialog shown, awaiting result
system dialog result | resultCode=-1 (RESULT_OK=-1, RESULT_CANCELED=0) | pendingUris=3
post-dialog verify | uri=... | stillExists=false | mediaStoreLookup=ok | rows=0
===== delete summary ===== deleted=3 | failed=0 | cancelled=false
failure | uri=... | reason=Access to this file was denied.
```

`post-dialog verify` distinguishes "the system said OK but the row survived"
from a genuine deletion — the case that would otherwise be reported as success.

## Supporting change

`PlatformDeleteRepository` now sends a `debugItems` list alongside `uris`,
carrying each item's category, name, path, size and MIME type. It exists purely
so the logs are readable; **routing still depends only on the URI**, and the
native side never consults it for a decision.

## What was deliberately not touched

- No deletion strategy changed.
- No UI, selection, permission or manifest changes.
- No `MANAGE_EXTERNAL_STORAGE`.
- No new speculative fix.

The only non-logging edits are two mechanical refactors needed to log at all: a
`stillExists(uri)` call hoisted into a local so its value can be printed, and
`buildResponse` converted from an expression body to a block body so it can log
before returning the same map.

## What to send back

The `[DELETE_DEBUG]` output for one failing delete — ideally one image and one
document — from `===== delete request` through `===== delete summary`. That
should identify the branch and the exact exception, and the real fix follows
from there.
