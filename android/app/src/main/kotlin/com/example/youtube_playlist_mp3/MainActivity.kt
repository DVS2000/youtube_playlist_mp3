package com.example.youtube_playlist_mp3

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mp3_saver")
            .setMethodCallHandler { call, result ->
                if (call.method == "listSavedAudio") {
                    val folder = call.argument<String>("folder") ?: ""
                    Thread {
                        try {
                            val rows = listSavedAudio(folder)
                            runOnUiThread { result.success(rows) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("LIST_FAILED", e.message, null) }
                        }
                    }.start()
                } else if (call.method == "saveToMusic") {
                    val path = call.argument<String>("path")!!
                    val name = call.argument<String>("name")!!
                    val folder = call.argument<String>("folder")!!
                    Thread {
                        try {
                            val saved = saveToMusic(path, name, folder)
                            runOnUiThread { result.success(mapOf("location" to saved.first, "uri" to saved.second)) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SAVE_FAILED", e.message, null) }
                        }
                    }.start()
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun listSavedAudio(folder: String): List<Map<String, String>> {
        val rows = mutableListOf<Map<String, String>>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.RELATIVE_PATH,
        )
        val selection = "${MediaStore.Audio.Media.RELATIVE_PATH} LIKE ?"
        val relative = if (folder.startsWith("Music/")) folder else "Music/$folder"
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            arrayOf("$relative/%"),
            "${MediaStore.Audio.Media.DISPLAY_NAME} ASC",
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idIndex)
                val uri = android.content.ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    id,
                )
                rows.add(mapOf("name" to cursor.getString(nameIndex), "uri" to uri.toString()))
            }
        }
        return rows
    }

    /** Copies [path] to Music/[folder]/[name] and returns the public location. */
    private fun saveToMusic(path: String, name: String, folder: String): Pair<String, String> {
        val source = File(path)
        val relative = "${Environment.DIRECTORY_MUSIC}/$folder"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, name)
                put(MediaStore.Audio.Media.MIME_TYPE, "audio/mpeg")
                put(MediaStore.Audio.Media.RELATIVE_PATH, relative)
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Não foi possível criar o ficheiro")
            resolver.openOutputStream(uri)!!.use { out ->
                FileInputStream(source).use { it.copyTo(out) }
            }
            values.clear()
            values.put(MediaStore.Audio.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            return Pair(relative, uri.toString())
        } else {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), folder)
            dir.mkdirs()
            val dest = File(dir, name)
            source.copyTo(dest, overwrite = true)
            android.media.MediaScannerConnection.scanFile(this, arrayOf(dest.absolutePath), null, null)
            return Pair(relative, dest.absolutePath)
        }
    }
}
