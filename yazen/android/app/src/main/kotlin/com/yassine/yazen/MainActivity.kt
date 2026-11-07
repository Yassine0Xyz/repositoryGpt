package com.yassine.yazen

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Debug
import android.os.Process
import android.os.StatFs
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.Settings
import android.content.ContentValues
import android.util.Log
import android.util.Rational
import android.util.Size
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.LinkedHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.roundToInt

class MainActivity : AudioServiceActivity() {
    private val channelName = "yazen/local_media"
    private val pcmTag = "YAZENPcm"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val deleteAudioRequestCode = 4207
    private var pendingVideoPermissionResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeleteIds: List<Int> = emptyList()
    private val pcmExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val artworkExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    // MediaStore enumeration and thumbnail decoding must never run on Flutter's
    // platform thread. Keep the two workloads isolated so a large library scan
    // cannot starve thumbnails for the currently visible video cards.
    private val videoQueryExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val videoThumbnailExecutor: ExecutorService = Executors.newFixedThreadPool(2)
    private val diagnosticsExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val pendingVideoQueryResults = mutableListOf<MethodChannel.Result>()
    private var videoQueryInFlight = false
    @Volatile
    private var activityDestroyed = false
    private var pcmGeneration = 0
    private var pcmState = "idle"
    private var pcmResult: PcmSpectrumAnalyzer.Result? = null
    private var pcmProgressFrames: MutableList<FloatArray> = mutableListOf()
    private val pcmCache = object : LinkedHashMap<String, PcmSpectrumAnalyzer.Result>(
        4,
        0.75f,
        true,
    ) {
        override fun removeEldestEntry(
            eldest: MutableMap.MutableEntry<String, PcmSpectrumAnalyzer.Result>?,
        ): Boolean = size > 3
    }
    private var pcmFailure: String? = null
    private var previousDiagnosticsCpuMs: Long? = null
    private var previousDiagnosticsWallMs: Long? = null
    private val previousThreadCpuTicks = mutableMapOf<Int, Long>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestVideoPermission" -> requestVideoPermission(result)
                    "videoPermissionStatus" -> result.success(hasVideoPermission())
                    "openAppSettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.parse("package:$packageName")
                                },
                            )
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("settings_unavailable", error.message, null)
                        }

                    }
                    "queryVideos" -> queryVideos(result)
                    "videoThumbnail" -> videoThumbnail(
                        call.argument<String>("uri"),
                        call.argument<Int>("width") ?: 640,
                        result,
                    )
                    "readArtworkPixels" -> readArtworkPixels(
                        call.argument<String>("uri"),
                        call.argument<Int>("size") ?: 64,
                        result,
                    )
                    "readOriginalArtwork" -> readOriginalArtwork(
                        call.argument<String>("uri"),
                        call.argument<Int>("size") ?: 256,
                        result,
                    )
                    "shareAudioTracks" -> shareAudioTracks(
                        call.argument<List<Int>>("ids"),
                        result,
                    )
                    "deleteAudioTracks" -> deleteAudioTracks(
                        call.argument<List<Int>>("ids"),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yazen/diagnostics")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "resourceSnapshot" -> {
                        val includeStorage = call.argument<Boolean>("includeStorage") == true
                        diagnosticsExecutor.execute {
                            try {
                                val snapshot = diagnosticResourceSnapshot(includeStorage)
                                mainHandler.post { result.success(snapshot) }
                            } catch (error: Exception) {
                                mainHandler.post { result.error("resource_snapshot_failed", error.message, null) }
                            }
                        }
                    }
                    "saveDiagnosticFiles" -> {
                        val files = call.arguments as? Map<*, *>
                        if (files == null) {
                            result.error("invalid_files", "No diagnostic report files were supplied.", null)
                        } else {
                            try {
                                result.success(saveDiagnosticFiles(files))
                            } catch (error: Exception) {
                                result.error("diagnostic_export_failed", error.message, null)
                            }
                        }
                    }
                    "exportDiagnosticJournal" -> exportDiagnosticJournal(
                        call.argument<String>("sourcePath"),
                        call.argument<String>("fileName"),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yazen/audio_visualizer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startPcm" -> startPcmAnalyzer(call.argument<String>("uri"), result)
                    "readPcm" -> readPcmAnalyzer(
                        call.argument<Number>("positionMs")?.toLong() ?: 0L,
                        result,
                    )
                    "stopPcm" -> {
                        stopPcmAnalyzer()
                        result.success(null)
                    }
                    "stop" -> {
                        stopPcmAnalyzer()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yazen/player_controls")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setVolume" -> {
                        val value = (call.argument<Number>("value")?.toFloat() ?: 0.75f)
                            .coerceIn(0f, 1f)
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        audioManager.setStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            (max * value).roundToInt(),
                            0,
                        )
                        result.success(null)
                    }
                    "setBrightness" -> {
                        val value = (call.argument<Number>("value")?.toFloat() ?: 0.65f)
                            .coerceIn(0.05f, 1f)
                        val attributes = window.attributes
                        attributes.screenBrightness = value
                        window.attributes = attributes
                        result.success(null)
                    }
                    "setKeepScreenOn" -> {
                        val keepScreenOn = call.argument<Boolean>("enabled") == true
                        if (keepScreenOn) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "enterPictureInPicture" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            enterPictureInPictureMode(
                                PictureInPictureParams.Builder()
                                    .setAspectRatio(Rational(16, 9))
                                    .build(),
                            )
                            result.success(null)
                        } else {
                            result.error("UNAVAILABLE", "Picture-in-picture requires Android 8.0 or newer.", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun diagnosticResourceSnapshot(includeStorage: Boolean): Map<String, Any> {
        val memory = Debug.MemoryInfo()
        Debug.getMemoryInfo(memory)
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val deviceMemory = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(deviceMemory)
        val dataDirectory = File(applicationInfo.dataDir)
        val storage = StatFs(dataDirectory.absolutePath)
        val nowWallMs = SystemClock.elapsedRealtime()
        val nowCpuMs = Process.getElapsedCpuTime()
        val previousWall = previousDiagnosticsWallMs
        val previousCpu = previousDiagnosticsCpuMs
        val cpuPercent = if (previousWall != null && previousCpu != null && nowWallMs > previousWall) {
            ((nowCpuMs - previousCpu).toDouble() / (nowWallMs - previousWall).toDouble() * 100.0)
        } else {
            -1.0
        }
        previousDiagnosticsWallMs = nowWallMs
        previousDiagnosticsCpuMs = nowCpuMs
        return mapOf(
            "pid" to Process.myPid(),
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "androidRelease" to Build.VERSION.RELEASE,
            "androidSdk" to Build.VERSION.SDK_INT,
            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
            "displayRefreshRateHz" to (windowManager.defaultDisplay.refreshRate.toDouble()),
            "displayWidthPx" to windowManager.defaultDisplay.width,
            "displayHeightPx" to windowManager.defaultDisplay.height,
            "processCpuTimeMs" to nowCpuMs,
            "processCpuPercentSincePreviousSnapshot" to cpuPercent,
            "processPssKb" to memory.totalPss,
            "processPrivateDirtyKb" to memory.totalPrivateDirty,
            "processPrivateCleanKb" to memory.totalPrivateClean,
            "javaHeapUsedBytes" to (Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()),
            "javaHeapMaxBytes" to Runtime.getRuntime().maxMemory(),
            "nativeHeapAllocatedBytes" to Debug.getNativeHeapAllocatedSize(),
            "nativeHeapFreeBytes" to Debug.getNativeHeapFreeSize(),
            "deviceAvailableMemoryBytes" to deviceMemory.availMem,
            "deviceTotalMemoryBytes" to deviceMemory.totalMem,
            "deviceLowMemory" to deviceMemory.lowMemory,
            "threadCpuSamples" to threadCpuSnapshot(),
            "runtimeGcStats" to Debug.getRuntimeStats(),
            "appDataBytes" to if (includeStorage) directorySize(dataDirectory) else -1L,
            "dataVolumeTotalBytes" to storage.totalBytes,
            "dataVolumeAvailableBytes" to storage.availableBytes,
        )
    }

    private fun threadCpuSnapshot(): List<Map<String, Any>> {
        val taskDirectory = File("/proc/self/task")
        val currentThreadIds = mutableSetOf<Int>()
        val samples = mutableListOf<Map<String, Any>>()
        taskDirectory.listFiles()?.forEach { threadDirectory ->
            val threadId = threadDirectory.name.toIntOrNull() ?: return@forEach
            try {
                val stat = File(threadDirectory, "stat").readText()
                val closingParenthesis = stat.lastIndexOf(')')
                if (closingParenthesis < 0 || closingParenthesis + 1 >= stat.length) return@forEach
                val fields = stat.substring(closingParenthesis + 1).trim().split(Regex("\\s+"))
                // After the comm field, index 11/12 are Linux stat fields 14/15 (utime/stime).
                if (fields.size <= 12) return@forEach
                val userTicks = fields[11].toLongOrNull() ?: return@forEach
                val systemTicks = fields[12].toLongOrNull() ?: return@forEach
                val totalTicks = userTicks + systemTicks
                val previous = previousThreadCpuTicks[threadId]
                val deltaTicks = if (previous == null) -1L else (totalTicks - previous).coerceAtLeast(0L)
                previousThreadCpuTicks[threadId] = totalTicks
                currentThreadIds.add(threadId)
                val threadName = try {
                    File(threadDirectory, "comm").readText().trim()
                } catch (_: Exception) {
                    "unknown"
                }
                samples.add(
                    mapOf(
                        "threadId" to threadId,
                        "name" to threadName,
                        "userTicks" to userTicks,
                        "systemTicks" to systemTicks,
                        "totalTicks" to totalTicks,
                        "deltaTicksSincePreviousSnapshot" to deltaTicks,
                    ),
                )
            } catch (_: Exception) {
                // Threads may exit while /proc is being enumerated.
            }
        }
        previousThreadCpuTicks.keys.retainAll(currentThreadIds)
        return samples.sortedByDescending { (it["deltaTicksSincePreviousSnapshot"] as? Long) ?: -1L }
    }

    private fun directorySize(directory: File): Long {
        var total = 0L
        val pending = java.util.ArrayDeque<File>()
        pending.add(directory)
        while (pending.isNotEmpty()) {
            val current = pending.removeFirst()
            val children = current.listFiles() ?: continue
            children.forEach { child ->
                if (child.isFile) total += child.length() else if (child.isDirectory) pending.add(child)
            }
        }
        return total
    }


    private fun exportDiagnosticJournal(
        sourcePath: String?,
        requestedFileName: String?,
        result: MethodChannel.Result,
    ) {
        if (sourcePath.isNullOrBlank() || requestedFileName.isNullOrBlank()) {
            result.error("invalid_journal", "A journal path and filename are required.", null)
            return
        }
        Thread {
            try {
                val source = File(sourcePath)
                if (!source.isFile) throw IllegalStateException("Session journal does not exist: $sourcePath")
                val safeName = requestedFileName.substringAfterLast('/').replace(Regex("[^A-Za-z0-9._-]"), "_")
                val savedPath: String
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                        put(MediaStore.MediaColumns.MIME_TYPE, "application/x-ndjson")
                        put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/YAZEN Diagnostics")
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("Unable to create Downloads entry for $safeName")
                    contentResolver.openOutputStream(uri)?.use { output ->
                        source.inputStream().buffered().use { input -> input.copyTo(output, 64 * 1024) }
                    } ?: throw IllegalStateException("Unable to open Downloads output stream")
                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                    savedPath = uri.toString()
                } else {
                    val directory = getExternalFilesDir(android.os.Environment.DIRECTORY_DOCUMENTS) ?: filesDir
                    val target = File(directory, safeName)
                    source.inputStream().buffered().use { input -> target.outputStream().buffered().use { output -> input.copyTo(output, 64 * 1024) } }
                    savedPath = target.absolutePath
                }
                runOnUiThread { result.success(savedPath) }
            } catch (error: Exception) {
                runOnUiThread { result.error("diagnostic_journal_export_failed", error.message, null) }
            }
        }.start()
    }

    private fun saveDiagnosticFiles(files: Map<*, *>): List<String> {
        val saved = mutableListOf<String>()
        files.forEach { (rawName, rawContent) ->
            val name = rawName as? String ?: return@forEach
            val content = rawContent as? String ?: return@forEach
            val safeName = name.substringAfterLast('/').replace(Regex("[^A-Za-z0-9._-]"), "_")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                    put(MediaStore.MediaColumns.MIME_TYPE, if (safeName.endsWith(".json")) "application/json" else "text/plain")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/YAZEN Diagnostics")
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("Unable to create Downloads entry for $safeName")
                contentResolver.openOutputStream(uri)?.bufferedWriter(Charsets.UTF_8)?.use { it.write(content) }
                    ?: throw IllegalStateException("Unable to write $safeName")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                saved.add(uri.toString())
            } else {
                val directory = getExternalFilesDir(android.os.Environment.DIRECTORY_DOCUMENTS)
                    ?: filesDir
                val target = File(directory, safeName)
                target.writeText(content, Charsets.UTF_8)
                saved.add(target.absolutePath)
            }
        }
        return saved
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == deleteAudioRequestCode) {
            val result = pendingDeleteResult
            val ids = pendingDeleteIds
            pendingDeleteResult = null
            pendingDeleteIds = emptyList()
            if (result != null) {
                if (resultCode == Activity.RESULT_OK) {
                    result.success(ids)
                } else {
                    result.error("delete_denied", "Audio deletion was cancelled.", null)
                }
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun shareAudioTracks(ids: List<Int>?, result: MethodChannel.Result) {
        val trackIds = ids?.distinct().orEmpty()
        if (trackIds.isEmpty()) {
            result.error("invalid_tracks", "No audio tracks were selected.", null)
            return
        }
        try {
            val streams = ArrayList(trackIds.map { id ->
                ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    id.toLong(),
                )
            })
            val intent = if (streams.size == 1) {
                Intent(Intent.ACTION_SEND).apply {
                    type = "audio/*"
                    putExtra(Intent.EXTRA_STREAM, streams.first())
                }
            } else {
                Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    type = "audio/*"
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, streams)
                }
            }.apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = android.content.ClipData.newUri(
                    contentResolver,
                    "YAZEN audio",
                    streams.first(),
                ).also { clip ->
                    streams.drop(1).forEach {
                        clip.addItem(android.content.ClipData.Item(it))
                    }
                }
            }
            startActivity(Intent.createChooser(intent, "Share audio"))
            result.success(null)
        } catch (error: Exception) {
            result.error("share_failed", error.message ?: "Unable to share audio.", null)
        }
    }

    private fun deleteAudioTracks(ids: List<Int>?, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.error(
                "delete_unsupported",
                "Secure audio deletion requires Android 11 or newer.",
                null,
            )
            return
        }
        val trackIds = ids?.distinct().orEmpty()
        if (trackIds.isEmpty()) {
            result.error("invalid_tracks", "No audio tracks were selected.", null)
            return
        }
        if (pendingDeleteResult != null) {
            result.error("delete_in_progress", "A delete request is already active.", null)
            return
        }
        val uris = trackIds.map { id ->
            ContentUris.withAppendedId(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                id.toLong(),
            )
        }
        try {
            val request = MediaStore.createDeleteRequest(contentResolver, uris)
            pendingDeleteIds = trackIds
            pendingDeleteResult = result
            startIntentSenderForResult(
                request.intentSender,
                deleteAudioRequestCode,
                null,
                0,
                0,
                0,
            )
        } catch (error: Exception) {
            pendingDeleteResult = null
            pendingDeleteIds = emptyList()
            result.error(
                "delete_failed",
                error.message ?: "Unable to request audio deletion.",
                null,
            )
        }
    }

    private fun startPcmAnalyzer(uriString: String?, result: MethodChannel.Result) {
        stopPcmAnalyzer()
        if (uriString.isNullOrBlank()) {
            result.success(mapOf<String, Any>("started" to false, "state" to "unavailable"))
            return
        }
        val generation = ++pcmGeneration
        val cached = pcmCache[uriString]
        if (cached != null) {
            pcmResult = cached
            pcmProgressFrames = cached.frames.toMutableList()
            pcmState = "ready"
            pcmFailure = null
            Log.i(
                pcmTag,
                "pcm cache hit uri=$uriString frames=${cached.frames.size}",
            )
            result.success(
                mapOf<String, Any>(
                    "started" to true,
                    "mode" to "pcm_file_cache",
                    "state" to "ready",
                ),
            )
            return
        }
        pcmState = "preparing"
        pcmResult = null
        pcmProgressFrames = mutableListOf()
        pcmFailure = null
        Log.i(pcmTag, "pcm start requested uri=$uriString")
        result.success(
            mapOf<String, Any>(
                "started" to true,
                "mode" to "pcm_file",
                "state" to "preparing",
            ),
        )
        pcmExecutor.execute {
            val analysis = PcmSpectrumAnalyzer(contentResolver) {
                generation != pcmGeneration
            }.analyze(Uri.parse(uriString)) { frames ->
                mainHandler.post {
                    if (generation != pcmGeneration) return@post
                    pcmProgressFrames.addAll(frames)
                }
            }
            mainHandler.post {
                if (generation != pcmGeneration) return@post
                if (analysis == null) {
                    if (pcmProgressFrames.isEmpty()) {
                        pcmState = "unavailable"
                        pcmFailure = "decoder_failed"
                    } else {
                        pcmState = "ready"
                    }
                    Log.w(pcmTag, "pcm analysis unavailable uri=$uriString frames=${pcmProgressFrames.size}")
                } else {
                    pcmCache[uriString] = analysis
                    pcmResult = analysis
                    pcmProgressFrames = analysis.frames.toMutableList()
                    pcmState = "ready"
                    Log.i(
                        pcmTag,
                        "pcm ready uri=$uriString frames=${analysis.frames.size} " +
                            "frameMs=${analysis.frameDurationMs} sampleRate=${analysis.sampleRate} " +
                            "channels=${analysis.channels}",
                    )
                }
            }
        }
    }

    private fun readPcmAnalyzer(positionMs: Long, result: MethodChannel.Result) {
        val analysis = pcmResult
        val frameDurationMs = analysis?.frameDurationMs ?: 40L
        val frames = if (analysis != null) analysis.frames else pcmProgressFrames
        if (frames.isEmpty()) {
            if (pcmState == "preparing") {
                result.success(mapOf<String, Any>("state" to "preparing"))
            } else {
                result.success(
                    mapOf<String, Any>(
                        "state" to "unavailable",
                        "error" to (pcmFailure ?: "not_ready"),
                    ),
                )
            }
            return
        }
        val index = (positionMs / frameDurationMs).coerceAtLeast(0L).toInt()
        if (index >= frames.size) {
            val state = if (pcmState == "preparing") "preparing" else "unavailable"
            result.success(
                mapOf<String, Any>(
                    "state" to state,
                    "error" to (pcmFailure ?: if (state == "unavailable") "analysis_failed" else "not_ready"),
                ),
            )
            return
        }
        if (pcmState != "ready" && pcmState != "preparing") {
            result.success(
                mapOf<String, Any>(
                    "state" to "unavailable",
                    "error" to (pcmFailure ?: "not_ready"),
                ),
            )
            return
        }
        val frame = frames[index]
        result.success(
            mapOf<String, Any>(
                "state" to "live",
                "frameIndex" to index,
                "frameCount" to frames.size,
                "frameDurationMs" to frameDurationMs,
                "bands" to frame.toList(),
            ),
        )
    }

    private fun stopPcmAnalyzer() {
        pcmGeneration++
        pcmState = "idle"
        pcmResult = null
        pcmProgressFrames = mutableListOf()
        pcmFailure = null
    }

    private fun videoPermission(): String = if (Build.VERSION.SDK_INT >= 33) {
        Manifest.permission.READ_MEDIA_VIDEO
    } else {
        Manifest.permission.READ_EXTERNAL_STORAGE
    }

    private fun hasVideoPermission(): Boolean {
        val fullAccess =
            checkSelfPermission(videoPermission()) == PackageManager.PERMISSION_GRANTED
        val selectedAccess = Build.VERSION.SDK_INT >= 34 &&
            checkSelfPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) ==
            PackageManager.PERMISSION_GRANTED
        return fullAccess || selectedAccess
    }

    private fun requestVideoPermission(result: MethodChannel.Result) {
        if (hasVideoPermission()) {
            result.success(true)
            return
        }
        pendingVideoPermissionResult = result
        val permissions = if (Build.VERSION.SDK_INT >= 34) {
            arrayOf(
                videoPermission(),
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
        } else {
            arrayOf(videoPermission())
        }
        requestPermissions(permissions, 9001)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 9001) {
            pendingVideoPermissionResult?.success(hasVideoPermission())
            pendingVideoPermissionResult = null
        }
    }

    private fun videoThumbnail(
        uriString: String?,
        requestedWidth: Int,
        result: MethodChannel.Result,
    ) {
        if (!hasVideoPermission() || uriString.isNullOrBlank()) {
            result.success(null)
            return
        }
        val uri = runCatching { Uri.parse(uriString) }.getOrNull()
        if (uri == null || uri.scheme != "content") {
            result.success(null)
            return
        }
        val width = requestedWidth.coerceIn(160, 1200)
        try {
            videoThumbnailExecutor.execute {
                var bitmap: Bitmap? = null
                val bytes = try {
                    bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        contentResolver.loadThumbnail(uri, Size(width, width), null)
                    } else {
                        val id = ContentUris.parseId(uri)
                        MediaStore.Video.Thumbnails.getThumbnail(
                            contentResolver,
                            id,
                            MediaStore.Video.Thumbnails.MINI_KIND,
                            null,
                        )
                    }
                    bitmap?.let { thumbnail ->
                        ByteArrayOutputStream().use { output ->
                            if (thumbnail.compress(Bitmap.CompressFormat.JPEG, 86, output)) {
                                output.toByteArray()
                            } else {
                                null
                            }
                        }
                    }
                } catch (_: SecurityException) {
                    null
                } catch (_: Exception) {
                    null
                } finally {
                    bitmap?.recycle()
                }
                mainHandler.post {
                    if (!activityDestroyed) {
                        result.success(bytes)
                    } else {
                        runCatching {
                            result.error("activity_destroyed", "The activity closed during thumbnail loading.", null)
                        }
                    }
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            result.error("thumbnail_executor_closed", "Thumbnail loading is unavailable because the activity is closing.", null)
        }
    }

    private fun readArtworkPixels(
        uriString: String?,
        requestedSize: Int,
        result: MethodChannel.Result,
    ) {
        if (uriString.isNullOrBlank()) {
            result.success(null)
            return
        }
        val uri = runCatching { Uri.parse(uriString) }.getOrNull()
        if (uri == null) {
            result.success(null)
            return
        }
        val size = requestedSize.coerceIn(16, 128)
        artworkExecutor.execute {
            val pixels = try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                contentResolver.openInputStream(uri)?.use { input ->
                    BitmapFactory.decodeStream(input, null, bounds)
                }
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                    null
                } else {
                    var sample = 1
                    while (bounds.outWidth / (sample * 2) >= size &&
                        bounds.outHeight / (sample * 2) >= size
                    ) {
                        sample *= 2
                    }
                    val options = BitmapFactory.Options().apply { inSampleSize = sample }
                    val decoded = contentResolver.openInputStream(uri)?.use { input ->
                        BitmapFactory.decodeStream(input, null, options)
                    }
                    if (decoded == null) {
                        null
                    } else {
                        val scaled = Bitmap.createScaledBitmap(decoded, size, size, true)
                        val output = IntArray(size * size)
                        scaled.getPixels(output, 0, size, 0, 0, size, size)
                        if (scaled !== decoded) scaled.recycle()
                        decoded.recycle()
                        output.toList()
                    }
                }
            } catch (_: Exception) {
                null
            }
            mainHandler.post { result.success(pixels) }
        }
    }

    private fun readOriginalArtwork(
        uriString: String?,
        requestedSize: Int,
        result: MethodChannel.Result,
    ) {
        if (uriString.isNullOrBlank()) {
            result.success(null)
            return
        }
        val uri = runCatching { Uri.parse(uriString) }.getOrNull()
        if (uri == null) {
            result.success(null)
            return
        }
        val targetSize = requestedSize.coerceIn(16, 2048)
        artworkExecutor.execute {
            val artwork = try {
                val retriever = MediaMetadataRetriever()
                val embedded = try {
                    if (uri.scheme == "file") {
                        val path = uri.path
                        if (path.isNullOrBlank()) null else {
                            retriever.setDataSource(path)
                            retriever.embeddedPicture
                        }
                    } else {
                        retriever.setDataSource(applicationContext, uri)
                        retriever.embeddedPicture
                    }
                } finally {
                    runCatching { retriever.release() }
                }
                embedded?.takeIf { it.isNotEmpty() && it.size <= 24 * 1024 * 1024 }?.let {
                    decodeEmbeddedArtworkThumbnail(it, targetSize)
                }
            } catch (_: Exception) {
                null
            }
            mainHandler.post { result.success(artwork) }
        }
    }

    /** Decode embedded cover art near its display size, not at source resolution. */
    private fun decodeEmbeddedArtworkThumbnail(
        encoded: ByteArray,
        targetSize: Int,
    ): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(encoded, 0, encoded.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sampleSize = 1
        while (
            maxOf(bounds.outWidth, bounds.outHeight) / (sampleSize * 2) >= targetSize
        ) {
            sampleSize *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        val decoded = BitmapFactory.decodeByteArray(encoded, 0, encoded.size, options)
            ?: return null
        var outputBitmap: Bitmap? = null
        try {
            val scale = minOf(
                1.0,
                targetSize.toDouble() / maxOf(decoded.width, decoded.height),
            )
            val width = (decoded.width * scale).roundToInt().coerceAtLeast(1)
            val height = (decoded.height * scale).roundToInt().coerceAtLeast(1)
            val rendered = if (width != decoded.width || height != decoded.height) {
                Bitmap.createScaledBitmap(decoded, width, height, true)
            } else {
                decoded
            }
            outputBitmap = rendered
            val output = ByteArrayOutputStream()
            try {
                if (!rendered.compress(Bitmap.CompressFormat.JPEG, 86, output)) return null
                return output.toByteArray()
            } finally {
                output.close()
            }
        } finally {
            if (outputBitmap != null && outputBitmap !== decoded) outputBitmap?.recycle()
            decoded.recycle()
        }
    }

    private fun queryVideos(result: MethodChannel.Result) {
        if (activityDestroyed) {
            result.error("activity_destroyed", "The activity is closing.", null)
            return
        }
        if (!hasVideoPermission()) {
            result.success(emptyList<Map<String, Any>>())
            return
        }

        // Coalesce concurrent refresh requests into one MediaStore traversal.
        // The Flutter side also bounds thumbnail demand, so this executor never
        // competes with thumbnail decoding on the platform thread.
        pendingVideoQueryResults.add(result)
        if (videoQueryInFlight) return
        videoQueryInFlight = true
        try {
            videoQueryExecutor.execute {
                val videos = runCatching { queryVideosBlocking() }
                mainHandler.post {
                    videoQueryInFlight = false
                    if (activityDestroyed) return@post
                    val waiting = pendingVideoQueryResults.toList()
                    pendingVideoQueryResults.clear()
                    waiting.forEach { pending ->
                        runCatching {
                            videos.fold(
                                onSuccess = { pending.success(it) },
                                onFailure = {
                                    pending.error(
                                        "video_query_failed",
                                        it.message ?: "Unable to scan local videos.",
                                        null,
                                    )
                                },
                            )
                        }
                    }
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            videoQueryInFlight = false
            pendingVideoQueryResults.remove(result)
            result.error("video_query_unavailable", "Video indexing is unavailable because the activity is closing.", null)
        }
    }

    private fun queryVideosBlocking(): List<Map<String, Any>> {
        if (!hasVideoPermission()) return emptyList()
        val videos = LinkedHashMap<String, Map<String, Any>>()
        try {
            val collections = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.getExternalVolumeNames(this)
                    .map { volume -> MediaStore.Video.Media.getContentUri(volume) }
                    .ifEmpty { listOf(MediaStore.Video.Media.EXTERNAL_CONTENT_URI) }
            } else {
                listOf(MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
            }
            collections.forEach { collection ->
                val projection = arrayOf(
                    MediaStore.Video.Media._ID,
                    MediaStore.Video.Media.DATA,
                    MediaStore.Video.Media.DISPLAY_NAME,
                    MediaStore.Video.Media.DURATION,
                    MediaStore.Video.Media.SIZE,
                    MediaStore.Video.Media.DATE_ADDED,
                )
                contentResolver.query(
                    collection,
                    projection,
                    null,
                    null,
                    "${MediaStore.Video.Media.DATE_ADDED} DESC",
                )?.use { cursor ->
                    val idIndex = cursor.getColumnIndex(MediaStore.Video.Media._ID)
                    val pathIndex = cursor.getColumnIndex(MediaStore.Video.Media.DATA)
                    val nameIndex = cursor.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
                    val durationIndex = cursor.getColumnIndex(MediaStore.Video.Media.DURATION)
                    val sizeIndex = cursor.getColumnIndex(MediaStore.Video.Media.SIZE)
                    val dateIndex = cursor.getColumnIndex(MediaStore.Video.Media.DATE_ADDED)
                    while (cursor.moveToNext()) {
                        if (idIndex < 0) continue
                        val id = cursor.getLong(idIndex)
                        val uri = ContentUris.withAppendedId(collection, id)
                        val name = if (nameIndex >= 0) {
                            cursor.getString(nameIndex) ?: "Local video"
                        } else {
                            "Local video"
                        }
                        val path = if (pathIndex >= 0) {
                            cursor.getString(pathIndex).orEmpty()
                        } else {
                            ""
                        }
                        val duration = if (durationIndex >= 0) cursor.getLong(durationIndex) else 0L
                        val size = if (sizeIndex >= 0) cursor.getLong(sizeIndex) else 0L
                        val date = if (dateIndex >= 0) cursor.getLong(dateIndex) else 0L
                        // URI identity avoids collisions between two same-named
                        // videos that happen to have the same byte size.
                        videos[uri.toString()] = mapOf(
                            "path" to path,
                            "uri" to uri.toString(),
                            "title" to name,
                            "durationMs" to duration,
                            "sizeBytes" to size,
                            "dateAdded" to date,
                        )
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                val projection = arrayOf(
                    MediaStore.Downloads._ID,
                    MediaStore.Downloads.DISPLAY_NAME,
                    MediaStore.Downloads.MIME_TYPE,
                    MediaStore.Downloads.SIZE,
                    MediaStore.Downloads.DATE_ADDED,
                )
                contentResolver.query(
                    collection,
                    projection,
                    null,
                    null,
                    "${MediaStore.Downloads.DATE_ADDED} DESC",
                )?.use { cursor ->
                    val idIndex = cursor.getColumnIndex(MediaStore.Downloads._ID)
                    val nameIndex = cursor.getColumnIndex(MediaStore.Downloads.DISPLAY_NAME)
                    val mimeIndex = cursor.getColumnIndex(MediaStore.Downloads.MIME_TYPE)
                    val sizeIndex = cursor.getColumnIndex(MediaStore.Downloads.SIZE)
                    val dateIndex = cursor.getColumnIndex(MediaStore.Downloads.DATE_ADDED)
                    while (cursor.moveToNext()) {
                        if (idIndex < 0 || nameIndex < 0) continue
                        val name = cursor.getString(nameIndex) ?: continue
                        val mime = if (mimeIndex >= 0) cursor.getString(mimeIndex).orEmpty() else ""
                        val isVideo = mime.startsWith("video/") ||
                            name.substringAfterLast('.', "").lowercase() in
                            setOf("mp4", "mkv", "webm", "mov", "avi", "3gp", "m4v", "ts")
                        if (!isVideo) continue
                        val id = cursor.getLong(idIndex)
                        val uri = ContentUris.withAppendedId(collection, id)
                        val size = if (sizeIndex >= 0) cursor.getLong(sizeIndex) else 0L
                        val date = if (dateIndex >= 0) cursor.getLong(dateIndex) else 0L
                        videos.putIfAbsent(
                            uri.toString(),
                            mapOf(
                                "path" to "",
                                "uri" to uri.toString(),
                                "title" to name,
                                "durationMs" to 0L,
                                "sizeBytes" to size,
                                "dateAdded" to date,
                            ),
                        )
                    }
                }
            }
        } catch (_: SecurityException) {
            // Return the successfully scanned subset when permission is partial
            // or revoked during traversal.
        } catch (_: Exception) {
            // A provider failure should not crash the Activity or Flutter UI.
        }
        return videos.values.sortedByDescending { it["dateAdded"] as? Long ?: 0L }
    }

    override fun onDestroy() {
        stopPcmAnalyzer()
        activityDestroyed = true
        val waiting = pendingVideoQueryResults.toList()
        pendingVideoQueryResults.clear()
        waiting.forEach { pending ->
            runCatching {
                pending.error("activity_destroyed", "The activity was closed during video indexing.", null)
            }
        }
        diagnosticsExecutor.shutdownNow()
        videoQueryExecutor.shutdownNow()
        videoThumbnailExecutor.shutdownNow()
        pcmExecutor.shutdownNow()
        artworkExecutor.shutdownNow()
        super.onDestroy()
    }

}
