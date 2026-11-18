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
 * are left alone: the plugin already copies those into the cache. The copies
 * made here also live in the cache, so the stock sheet deletes them when it
 * closes, as it does the plugin's.
 */
object SharedStreamCopier {
    private const val TAG = "SharedStreamCopier"

    fun normalise(context: Context, intent: Intent?) {
        if (intent == null) return
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri = stream(intent) ?: return
                val copied = copyIfDocument(context, uri, 0) ?: return
                intent.putExtra(Intent.EXTRA_STREAM, copied)
                intent.clipData = null
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = streams(intent) ?: return
                var changed = false
                val out = ArrayList<Uri>(uris.size)
                uris.forEachIndexed { i, uri ->
                    val copied = copyIfDocument(context, uri, i)
                    if (copied != null) changed = true
                    out.add(copied ?: uri)
                }
                if (changed) {
                    intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, out)
                    intent.clipData = null
                }
            }
        }
    }

    private fun copyIfDocument(context: Context, uri: Uri, index: Int): Uri? {
        if (uri.scheme != "content") return null
        if (!DocumentsContract.isDocumentUri(context, uri)) return null
        return try {
            val name = displayName(context, uri) ?: "photo.jpg"
            val dir = File(context.cacheDir, "shared").apply { mkdirs() }
            val target = File(dir, "${System.currentTimeMillis()}_${index}_$name")
            context.contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { input.copyTo(it) }
            } ?: return null
            Uri.fromFile(target)
        } catch (e: Exception) {
            Log.w(TAG, "Could not copy shared document $uri", e)
            null
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
