package fr.couchplay

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Mise à jour (lib/update/android_installer.dart) : ouvre l'installateur
        // d'Android sur l'APK téléchargé par l'app. Le chemin est fixe, rien ne
        // vient de Dart, et c'est le seul fichier exposé (res/xml/update_paths.xml).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "couchplay/update")
            .setMethodCallHandler { call, result ->
                if (call.method != "install") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val apk = File(cacheDir, "update/couchplay.apk")
                val uri = FileProvider.getUriForFile(this, "$packageName.update", apk)
                try {
                    startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                    )
                    result.success(null)
                } catch (e: ActivityNotFoundException) {
                    // Appareil sans installateur d'applications.
                    result.error("install", e.message, null)
                }
            }
    }
}
