package fr.couchplay

import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.StatFs
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Appareil (lib/television.dart) : TV ou non, pour adapter la saisie.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "couchplay/device")
            .setMethodCallHandler { call, result ->
                if (call.method != "isTelevision") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val uiMode = getSystemService(UI_MODE_SERVICE) as UiModeManager
                result.success(uiMode.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
            }
        // Mise à jour (lib/update/android_installer.dart) :
        // - install : ouvre l'installateur d'Android sur l'APK téléchargé par
        //   l'app. Le chemin est fixe, rien ne vient de Dart, et c'est le seul
        //   fichier exposé (res/xml/update_paths.xml).
        // - supported64BitAbis : architectures 64 bits de l'appareil, pour
        //   choisir l'APK arm64 même quand l'app installée tourne en armv7.
        // - freeSpace : octets libres du volume du cache (/data), où vont
        //   l'APK et l'installation : StatFs marche sur toutes les ABI.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "couchplay/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> install(result)
                    "supported64BitAbis" -> result.success(Build.SUPPORTED_64_BIT_ABIS.toList())
                    "freeSpace" -> result.success(StatFs(cacheDir.path).availableBytes)
                    else -> result.notImplemented()
                }
            }
    }

    private fun install(result: MethodChannel.Result) {
        val apk = File(cacheDir, "update/couchplay.apk")
        // L'APK d'une autre app s'installerait à côté, sans la
        // vérification de signature d'une mise à jour : refusé. Illisible,
        // l'installateur d'Android le refusera de lui-même.
        @Suppress("DEPRECATION")
        val archive = packageManager.getPackageArchiveInfo(apk.path, 0)
        if (archive != null && archive.packageName != packageName) {
            result.error("install", "APK d'une autre app", null)
            return
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.update", apk)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        // L'installateur du système seulement : une autre app qui déclare ce
        // filtre ne reçoit pas l'APK. Son paquet change selon l'appareil
        // (Google, AOSP, Fire OS) : cherché ici, jamais écrit en dur. Visible
        // grâce au <queries> du manifeste.
        @Suppress("DEPRECATION")
        val system = packageManager
            .queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            .firstOrNull { (it.activityInfo.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 }
            ?.activityInfo
        if (system != null) intent.setClassName(system.packageName, system.name)
        try {
            startActivity(intent)
            // false : aucun installateur du système trouvé, Android choisit
            // (intent implicite, écrit au journal par l'app).
            result.success(system != null)
        } catch (e: ActivityNotFoundException) {
            // Appareil sans installateur d'applications.
            result.error("install", e.message, null)
        }
    }
}
