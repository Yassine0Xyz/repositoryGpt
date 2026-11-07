package com.lucasjosino.on_audio_query.queries

import android.content.ContentResolver
import android.content.ContentUris
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.util.Size
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lucasjosino.on_audio_query.PluginProvider
import com.lucasjosino.on_audio_query.queries.helper.QueryHelper
import com.lucasjosino.on_audio_query.types.checkArtworkFormat
import com.lucasjosino.on_audio_query.types.checkArtworkType
import io.flutter.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import kotlin.math.roundToInt

class ArtworkQuery : ViewModel() {

    companion object {
        private const val TAG = "OnArtworksQuery"
    }

    private val helper = QueryHelper()
    private var type: Int = -1
    private var id: Number = 0
    private var quality: Int = 100
    private var size: Int = 200
    private var showDetailedLog: Boolean = false

    private lateinit var uri: Uri
    private lateinit var resolver: ContentResolver
    private lateinit var format: Bitmap.CompressFormat

    /**
     * Method to "query" artwork.
     */
    fun queryArtwork() {
        val call = PluginProvider.call()
        val result = PluginProvider.result()
        val context = PluginProvider.context()
        this.resolver = context.contentResolver
        this.showDetailedLog = PluginProvider.showDetailedLog

        id = call.argument<Number>("id")!!

        // If the 'size' is null, will be '200'.
        size = call.argument<Int>("size")!!

        // The 'quality' value cannot be greater than 100 so, we check and if is, set to '50'.
        quality = call.argument<Int>("quality")!!
        if (quality > 100) quality = 50

        // Check format:
        //   * 0 -> JPEG
        //   * 1 -> PNG
        format = checkArtworkFormat(call.argument<Int>("format")!!)

        // Check uri:
        //   * 0 -> Song.
        //   * 1 -> Album.
        //   * 2 -> Playlist.
        //   * 3 -> Artist.
        //   * 4 -> Genre.
        uri = checkArtworkType(call.argument<Int>("type")!!)

        // This query is 'universal' will work for multiple types (audio, album, artist, etc...).
        type = call.argument<Int>("type")!!

        Log.d(TAG, "Query config: ")
        Log.d(TAG, "\tid: $id")
        Log.d(TAG, "\tquality: $quality")
        Log.d(TAG, "\tformat: $format")
        Log.d(TAG, "\turi: $uri")
        Log.d(TAG, "\ttype: $type")

        // Query everything in background for a better performance.
        viewModelScope.launch {
            var resultArtList = loadArt()

            // Sometimes android will extract a 'wrong' or 'empty' artwork. Just set as null.
            if (resultArtList != null && resultArtList.isEmpty()) {
                Log.i(TAG, "Artwork for '$id' is empty. Returning null")
                resultArtList = null
            }

            result.success(resultArtList)
        }
    }

    //Loading in Background
    private suspend fun loadArt(): ByteArray? = withContext(Dispatchers.IO) {
        var artData: ByteArray? = null

        // If 'Android' >= 29/Q:
        //   * Limited access to files/folders. Use 'loadThumbnail'.
        // If 'Android' < 29/Q:
        //   * Use the 'embeddedPicture' from 'MediaMetadataRetriever' to get the image.
        if (Build.VERSION.SDK_INT >= 29) {
            try {
                // If 'type' is 2, 3 or 4, Get the first item from playlist or artist.
                // Use the first artist song to 'simulate' the artwork.
                //
                // Type:
                //   * 2 -> Playlist.
                //   * 3 -> Artist.
                //   * 4 -> Genre.
                //
                // OBS: The 'id' is defined as 'Number'. Convert to 'Long'
                val query = if (type == 2 || type == 3 || type == 4) {
                    val item = helper.loadFirstItem(type, id, resolver) ?: return@withContext null
                    ContentUris.withAppendedId(uri, item.toLong())
                } else {
                    ContentUris.withAppendedId(uri, id.toLong())
                }

                val bitmap = resolver.loadThumbnail(query, Size(size, size), null)
                artData = convertOrResize(bitmap = bitmap)!!
            } catch (e: Exception) {
                // This may produce a lot of logging on console so, will required a explicit request
                // to show the errors.
                if (showDetailedLog) Log.w(TAG, "($id) Message: $e")
            }
        } else {
            // If 'uri == Audio':
            //   * Load the first 'item' from cursor using the 'id' as filter.
            // else:
            //   * Load the first 'item' from 'album' using the 'id' as filter.
            //
            // If 'item' return null, no song/album has found, return null.
            val item = helper.loadFirstItem(type, id, resolver) ?: return@withContext null

            val file = FileInputStream(item)
            val metadata = MediaMetadataRetriever()
            try {
                metadata.setDataSource(file.fd)
                val image = metadata.embeddedPicture

                // Convert image. If null, return
                artData = convertOrResize(byteArray = image) ?: return@withContext null
            } catch (e: Exception) {
                // This may produce a lot of logging on console so, will require an explicit request
                // to show the errors.
                if (showDetailedLog) Log.w(TAG, "($id) Message: $e")
            } finally {
                // release() is available on older Android versions too. Always
                // close both native handles, including when artwork conversion fails.
                runCatching { metadata.release() }
                runCatching { file.close() }
            }
        }

        return@withContext artData
    }

    //
    private fun convertOrResize(
        bitmap: Bitmap? = null,
        byteArray: ByteArray? = null,
    ): ByteArray? {
        val output = ByteArrayOutputStream()
        var sourceBitmap: Bitmap? = bitmap
        var outputBitmap: Bitmap? = null

        try {
            if (sourceBitmap == null) {
                val encoded = byteArray ?: return null
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(encoded, 0, encoded.size, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

                // Older Android versions expose embedded artwork as its original
                // encoded bytes. Decode near the requested thumbnail size rather
                // than allocating a full-resolution bitmap for every list row.
                val targetSize = size.coerceIn(16, 2048)
                var sampleSize = 1
                while (
                    maxOf(bounds.outWidth, bounds.outHeight) / (sampleSize * 2) >= targetSize
                ) {
                    sampleSize *= 2
                }
                val options = BitmapFactory.Options().apply {
                    inSampleSize = sampleSize
                }
                sourceBitmap = BitmapFactory.decodeByteArray(
                    encoded,
                    0,
                    encoded.size,
                    options,
                ) ?: return null
            }

            val source = sourceBitmap ?: return null
            val targetSize = size.coerceIn(16, 2048)
            val scale = minOf(
                1.0,
                targetSize.toDouble() / maxOf(source.width, source.height),
            )
            val targetWidth = (source.width * scale).roundToInt().coerceAtLeast(1)
            val targetHeight = (source.height * scale).roundToInt().coerceAtLeast(1)
            val rendered =
                if (targetWidth != source.width || targetHeight != source.height) {
                    Bitmap.createScaledBitmap(source, targetWidth, targetHeight, true)
                } else {
                    source
                }
            outputBitmap = rendered
            if (!rendered.compress(format, quality, output)) return null
            return output.toByteArray()
        } catch (e: Exception) {
            if (showDetailedLog) Log.w(TAG, "($id) Message: $e")
            return null
        } finally {
            if (outputBitmap != null && outputBitmap !== sourceBitmap) {
                outputBitmap?.recycle()
            }
            sourceBitmap?.recycle()
            output.close()
        }
    }
}
