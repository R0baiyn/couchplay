package fr.couchplay

import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.StatFs
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var audioChannel: MethodChannel? = null
    private var focusRequest: AudioFocusRequest? = null
    private var focusHeld = false

    /// Perte du focus, définitive ou passagère : pause. Une notification
    /// courte (`CAN_DUCK`) ne fait rien, le système baisse le volume ; un
    /// retour du focus ne relance rien.
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change == AudioManager.AUDIOFOCUS_LOSS ||
            change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
        ) {
            interrupt("focus")
        }
    }

    /// Casque filaire ou Bluetooth débranché : pause.
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) interrupt("noisy")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Focus audio (lib/player/audio_focus.dart) :
        // - request : demande le focus (vrai s'il est accordé) et écoute le
        //   débranchement du casque tant qu'il est tenu ;
        // - abandon : rend le focus (sans effet s'il ne l'est plus).
        // Vers Dart : interrupted("focus" | "noisy"), le focus déjà rendu.
        audioChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "couchplay/audio")
            .apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "request" -> result.success(requestFocus())
                        "abandon" -> {
                            abandonFocus()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        abandonFocus()
        audioChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private val audioManager get() = getSystemService(AUDIO_SERVICE) as AudioManager

    private fun requestFocus(): Boolean {
        val audio = audioManager
        val answer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build(),
                )
                .setOnAudioFocusChangeListener(focusListener)
                .build()
                .also { focusRequest = it }
            audio.requestAudioFocus(request)
        } else {
            // Sous l'API 26, AudioFocusRequest n'existe pas.
            @Suppress("DEPRECATION")
            audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        val granted = answer == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (granted && !focusHeld) {
            // Diffusion protégée du système : aucune autre app ne l'envoie.
            registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
            focusHeld = true
        }
        return granted
    }

    private fun abandonFocus() {
        if (!focusHeld) return
        focusHeld = false
        unregisterReceiver(noisyReceiver)
        val request = focusRequest
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && request != null) {
            audioManager.abandonAudioFocusRequest(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
    }

    /// Rend le focus puis prévient Dart, sur le fil principal ; la lecture
    /// ne reprend jamais d'ici.
    private fun interrupt(reason: String) = runOnUiThread {
        abandonFocus()
        audioChannel?.invokeMethod("interrupted", reason)
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
            .setDataAndType(uri, APK_TYPE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val installer = systemInstaller(intent)
        if (installer != null) {
            try {
                startActivity(Intent(intent).setClassName(installer.packageName, installer.name))
                // Paquet de l'installateur, pour le journal de l'app.
                result.success(installer.packageName)
                return
            } catch (e: ActivityNotFoundException) {
                // Désactivé entre-temps : l'intent implicite, ci-dessous.
            } catch (e: SecurityException) {
                // Refusé : l'intent implicite, ci-dessous.
            }
        }
        try {
            startActivity(intent)
            // "" : Android choisit l'app (intent implicite), écrit au journal
            // de l'app.
            result.success("")
        } catch (e: ActivityNotFoundException) {
            // Appareil sans installateur d'applications.
            result.error("install", e.message, null)
        }
    }

    /// L'activité d'app système qui ouvre [view] (l'APK) : une autre app qui
    /// déclare ce filtre ne reçoit pas l'APK. Le paquet de l'installateur
    /// change selon l'appareil (Google, AOSP, Fire OS) : cherché ici, jamais
    /// écrit en dur, parmi les apps visibles grâce au <queries> du manifeste.
    /// Plusieurs apps système peuvent ouvrir un APK (gestionnaire de
    /// fichiers…) : d'abord celle qui gère aussi INSTALL_PACKAGE, que seul
    /// l'installateur de paquets déclare ; sinon la première app système ;
    /// sinon null (intent implicite, D-060).
    @Suppress("DEPRECATION")
    private fun systemInstaller(view: Intent): ActivityInfo? {
        fun system(intent: Intent) = packageManager
            .queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            .map { it.activityInfo }
            .filter { (it.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 }
        val viewers = system(view)
        val installers = system(
            Intent(Intent.ACTION_INSTALL_PACKAGE).setDataAndType(view.data, APK_TYPE),
        ).map { it.packageName }.toSet()
        return viewers.firstOrNull { it.packageName in installers } ?: viewers.firstOrNull()
    }

    private companion object {
        const val APK_TYPE = "application/vnd.android.package-archive"
    }
}
