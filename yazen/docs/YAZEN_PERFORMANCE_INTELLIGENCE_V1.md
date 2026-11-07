# YAZEN Performance Intelligence — V1 implementation notes

## Selected operating profile

- Investigation depth: Maximum Investigation.
- Operating mode: Hybrid (lightweight monitoring during normal sessions; deep-investigation mode can be enabled on demand).
- The diagnostic UI is a control/inspection surface. The append-only session journal and instrumentation are the actual system.

## Implemented in this source iteration

1. A per-session JSONL journal is created under the application documents directory. Events are appended asynchronously and flushed in batches. The dashboard keeps a separate bounded in-memory cache; export does not use that cache as its source of truth.
2. Each event has a sequence number, event ID, session ID, UTC wall timestamp, monotonic elapsed microseconds, route, type, payload, and optional trace/span identifiers.
3. Flutter frame timings are journaled per frame. Budget thresholds derive from the most recently sampled Android display refresh rate; a 60 Hz fallback is used until the first native sample. Summary percentiles are explicitly labeled as a recent rolling window.
4. Scroll notifications are recorded at each Flutter scroll update with microsecond intervals and calculated pixels/second velocity.
5. Pointer down/move/up/cancel samples are captured at the app root while a pointer is pressed. This records movement samples delivered by Flutter; it does not claim access to every physical touchscreen sensor sample, hover movement, or events suppressed before Flutter receives them.
6. Library query, snapshot-build, sorting/filtering/search, artwork gate/cache/source-fetch/decode/crop/write operations now expose trace/span IDs and duration outcomes. Selected playback and library-control actions are also journaled, including audio-handler state, queue transitions, sleep timer, EQ, audio interruptions, and periodic playback-position checkpoints. Frame records include active spans, scroll traces, and pointer traces to support timeline correlation.
7. The export produces a metadata/analysis JSON file, a readable Markdown report, and a companion JSONL journal copied to `Download/YAZEN Diagnostics` on supported Android versions. It freezes a sequence boundary, snapshots the journal, then resumes live writes before the expensive analysis step. The app-private journal remains the source of truth.
8. Native journal copying runs off the Android UI thread.
9. The diagnostics screen exposes actual counters, recording controls, deep-investigation toggle, journal health, sampled diagnostics-overhead metrics, and export. It is not treated as the diagnostic engine itself.

## Completeness and integrity semantics

- `journalEventsObserved` counts all events observed by the recorder.
- `journalEventsQueued` counts serialized events accepted into the pending journal queue.
- `journalEventsPersisted` counts lines flushed successfully to the session journal.
- `journalEventsDropped` counts events that could not be queued because the bounded pending queue was full or serialization failed.
- `journalError` reports persistent I/O/initialization failures.
- An export is only marked complete from session start when the journal is ready, no events were dropped, no journal error was observed, and the exported JSONL has matching persisted-event count, valid lines, and continuous ordered sequence numbers.
- The dashboard cache is capped at 12,000 events. It is not a complete session record.
- Pointer movement is recorded for active pointers, not hover. `ScrollUpdateNotification` samples and pointer movement samples are separate event types and should not be naively summed as unique gestures.

## Known limitations / next phases

- This iteration establishes the journal and first usable instrumentation across all eight areas, but several modules remain partial: Dart VM heap/GC, detailed widget build/layout/paint attribution in the JSONL, and OS-wide storage/I/O are not yet available from the in-app recorder.
- Android native snapshots now include per-thread Linux CPU tick deltas and ART runtime GC stats. Tick deltas are relative raw kernel ticks, not percentages or milliseconds; use Perfetto for definitive thread scheduling and CPU-time attribution.
- Dart heap and Dart garbage-collection metrics require VM service/Profile tooling; Android ART GC stats are captured separately. Per-widget memory attribution is not generally available.
- Maximum Investigation enables Flutter widget build, layout, and paint timeline profiling in Debug/Profile-capable builds. The detailed widget timeline is inspected through Flutter DevTools; it is not duplicated into the JSONL journal. Broad per-widget counters can materially distort results.
- Storage/I/O coverage currently includes only instrumented application operations, not every kernel/filesystem operation.
- The current analysis is deliberately conservative. Time overlap is reported as correlation, never proof of cause.
- Recorder serialization/queue cost is sampled once per 64 events, and journal drain/flush duration is measured per batch. These are diagnostic overhead indicators, not a complete CPU attribution.
- The journal queue is bounded to protect app responsiveness. Any overflow is surfaced as a dropped-event count and makes the export incomplete rather than silently claiming full fidelity.
- App termination by force-stop or power loss can leave the final buffered batch unwritten. Periodic flushes reduce but cannot eliminate this risk.
- No Flutter/Dart SDK was available in the editing environment; analyzer, test, APK build, and real-device overhead measurements remain pending.

## Validation required on the Galaxy A52

1. Build and run in Profile mode; verify the journal initializes and receives `session_start` before the first route events.
2. Perform tap, slow drag, fast drag, side-scrollbar drag, fling, multi-touch, app background/foreground, and route transitions.
3. Export and verify JSONL sequence continuity, pointer samples, scroll velocity, frame timings, and zero dropped events.
4. Compare the same scripted interaction with diagnostics disabled, Hybrid only, and Maximum Investigation enabled to quantify instrumentation overhead.
5. Repeat with cold/warm artwork cache and 300 / 1k / 3k / 5k / 10k track datasets.
6. Confirm the Downloads journal is byte-for-byte identical to the app-private journal.

## Important interpretation

The system can report every PointerEvent and ScrollNotification delivered to the Flutter application, every FrameTiming delivered by Flutter, and every operation instrumented by YAZEN. It cannot truthfully promise literal capture of every hardware touch-controller sample, every OS-internal event, or every instruction executed by the device. The report must always disclose those boundaries.
