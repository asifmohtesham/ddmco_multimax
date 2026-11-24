package com.ddmco.multimax

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import java.io.File

/**
 * Copies shared photos that arrive as *document* URIs into the app's cache
 * and swaps them for `file://` URIs, before receive_sharing_intent reads the
 * intent.
 *
 * receive_sharing_intent 1.9.0 resolves document URIs itself and gets two
 * kinds wrong:
 * - a Files-app document on internal storage becomes its raw
 *   `/storage/emulated/0/…` path, which the app has no permission to read;
 * - a MediaStore document (Files → Images) makes it open the whole images
 *   collection, which throws, so the plugin fails to register and the share
 *   is lost.
 *
 * Plain `content://` URIs (gallery apps, Google Photos, My Files, WhatsApp)
 * are left alone: the plugin already copies those into the cache. Both
 * paths use the cache for the initial transfer. ShareIntakeService stages
 * its own copy in app support storage before dispatching the share.
 *
 * A document URI that cannot be copied is dropped, never passed on, because
 * the plugin would throw on it. Copying runs on the main thread, as the
 * plugin's own copying does, because it must finish before the plugin reads
 * the intent.
 */
object SharedStreamCopier {
    private const val TAG = "SharedStreamCopier"

    /** Rewrites a share intent in place. Never throws. */
    fun normalise(context: Context, intent: Intent?) {
        if (intent == null) return
        try {
            when (intent.action) {
                Intent.ACTION_SEND -> {
                    val uri = stream(intent) ?: return
                    when (val r = copyIfDocument(context, uri, 0)) {
                        is Result.Copied -> {
                            intent.putExtra(Intent.EXTRA_STREAM, r.uri)
                            // The original URI is no longer read; the read
                            // grant belongs to the activity, not this field.
                            intent.clipData = null
                        }
                        Result.Failed -> dropShare(intent)
                        Result.NotDocument -> Unit
                    }
                }
                Intent.ACTION_SEND_MULTIPLE -> {
                    val uris = streams(intent) ?: return
                    var changed = false
                    val out = ArrayList<Uri>(uris.size)
                    uris.forEachIndexed { i, uri ->
                        when (val r = copyIfDocument(context, uri, i)) {
                            is Result.Copied -> { out.add(r.uri); changed = true }
                            Result.Failed -> changed = true
                            Result.NotDocument -> out.add(uri)
                        }
                    }
                    if (!changed) return
                    if (out.isEmpty()) {
                        dropShare(intent)
                    } else {
                        intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, out)
                        intent.clipData = null
                    }
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Could not prepare the shared photos; ignoring the share", t)
            dropShare(intent)
        }
    }

    /**
     * Turns a share into a plain launch, so receive_sharing_intent reports no
     * share. Used for a share that cannot be read, and for the stale share an
     * activity is restored with after the process was killed (its copies are
     * gone by then).
     */
    fun dropShare(intent: Intent) {
        if (intent.action != Intent.ACTION_SEND &&
            intent.action != Intent.ACTION_SEND_MULTIPLE) return
        intent.action = Intent.ACTION_MAIN
        intent.removeExtra(Intent.EXTRA_STREAM)
        intent.clipData = null
    }

    private sealed class Result {
        data class Copied(val uri: Uri) : Result()
        object Failed : Result()
        object NotDocument : Result()
    }

    private fun copyIfDocument(context: Context, uri: Uri?, index: Int): Result {
        if (uri == null) return Result.NotDocument
        if (uri.scheme != "content") return Result.NotDocument
        if (!DocumentsContract.isDocumentUri(context, uri)) return Result.NotDocument
        var target: File? = null
        return try {
            val name = (displayName(context, uri) ?: "photo.jpg").takeLast(120)
            val dir = File(context.cacheDir, "shared").apply { mkdirs() }
            val file = File(dir, "${System.currentTimeMillis()}_${index}_$name")
            target = file
            val input = context.contentResolver.openInputStream(uri)
                ?: return Result.Failed
            input.use { i -> file.outputStream().use { i.copyTo(it) } }
            Result.Copied(Uri.fromFile(file))
        } catch (e: Exception) {
            Log.w(TAG, "Could not copy shared document $uri", e)
            target?.delete()
            Result.Failed
        }
    }

    private fun displayName(context: Context, uri: Uri): String? = try {
        context.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
            ?.replace('/', '_')
    } catch (e: Exception) {
        null
    }

    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): ArrayList<Uri>? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }
}
