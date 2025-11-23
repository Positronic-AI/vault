package com.vault.vault

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.vault/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApkPath" -> {
                    try {
                        val apkPath = applicationContext.applicationInfo.sourceDir
                        result.success(apkPath)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to get APK path", e.message)
                    }
                }
                "getCertificateFingerprint" -> {
                    try {
                        val fingerprint = getCertificateFingerprint()
                        result.success(fingerprint)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to get certificate fingerprint", e.message)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getCertificateFingerprint(): String {
        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_SIGNING_CERTIFICATES
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_SIGNATURES
            )
        }

        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.signingInfo?.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            packageInfo.signatures
        }

        if (signatures.isNullOrEmpty()) {
            return "No signature found"
        }

        val cert = signatures[0].toByteArray()
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(cert)

        return digest.joinToString(":") { "%02X".format(it) }
    }
}
