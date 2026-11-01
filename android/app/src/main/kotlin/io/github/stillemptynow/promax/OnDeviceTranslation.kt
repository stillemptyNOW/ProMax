package io.github.stillemptynow.promax

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.languageid.LanguageIdentification
import com.google.mlkit.nl.languageid.LanguageIdentificationOptions
import com.google.mlkit.nl.languageid.LanguageIdentifier
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object OnDeviceTranslation {

    private const val CHANNEL = "io.github.stillemptynow.promax/translate"
    private const val UNDETERMINED = "und"
    private const val CONFIDENCE = 0.5f
    private const val MAX_TRANSLATORS = 3

    private val translators = LinkedHashMap<String, Translator>(MAX_TRANSLATORS, 0.75f, true)
    private var identifier: LanguageIdentifier? = null

    fun attach(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capabilities" -> result.success(
                        mapOf(
                            "available" to true,
                            "manageModels" to true,
                            "wifiOnlyOption" to true,
                        ),
                    )
                    "detect" -> detect(call, result)
                    "translate" -> translate(app, call, result)
                    "models" -> models(result)
                    "deleteModel" -> deleteModel(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun identifier(): LanguageIdentifier =
        identifier ?: LanguageIdentification.getClient(
            LanguageIdentificationOptions.Builder()
                .setConfidenceThreshold(CONFIDENCE)
                .build(),
        ).also { identifier = it }

    private fun identify(text: String): Task<String?> =
        identifier().identifyLanguage(text).continueWith { task ->
            val code = if (task.isSuccessful) task.result else null
            if (code == null || code == UNDETERMINED) null else code
        }

    private fun detect(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")
        if (text.isNullOrBlank()) {
            result.success(null)
            return
        }
        identify(text).addOnCompleteListener { task ->
            result.success(if (task.isSuccessful) task.result else null)
        }
    }

    private fun translate(context: Context, call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")
        val targetTag = call.argument<String>("target")
        val sourceTag = call.argument<String>("source")
        val wifiOnly = call.argument<Boolean>("wifiOnly") ?: false
        if (text.isNullOrBlank() || targetTag == null) {
            result.error("invalid", "text and target are required", null)
            return
        }
        val target = TranslateLanguage.fromLanguageTag(targetTag)
        if (target == null) {
            result.error("unsupported", "target $targetTag is not supported", null)
            return
        }
        if (sourceTag != null) {
            translateFrom(context, text, sourceTag, target, wifiOnly, result)
            return
        }
        identify(text).addOnCompleteListener { task ->
            val detected = if (task.isSuccessful) task.result else null
            if (detected == null) {
                result.error("undetermined", "source language is unknown", null)
            } else {
                translateFrom(context, text, detected, target, wifiOnly, result)
            }
        }
    }

    private fun translateFrom(
        context: Context,
        text: String,
        sourceTag: String,
        target: String,
        wifiOnly: Boolean,
        result: MethodChannel.Result,
    ) {
        val source = TranslateLanguage.fromLanguageTag(sourceTag)
        if (source == null) {
            result.error("unsupported", "source $sourceTag is not supported", null)
            return
        }
        if (source == target) {
            result.success(mapOf("text" to text, "source" to source, "same" to true))
            return
        }
        val manager = RemoteModelManager.getInstance()
        val checks = listOf(source, target).distinct().map {
            manager.isModelDownloaded(TranslateRemoteModel.Builder(it).build())
        }
        Tasks.whenAllSuccess<Boolean>(checks).addOnCompleteListener { check ->
            val ready = check.isSuccessful && check.result.all { it }
            if (!ready && wifiOnly && !onUnmeteredNetwork(context)) {
                result.error("needs_wifi", "models download only over Wi-Fi", null)
                return@addOnCompleteListener
            }
            val translator = translator(source, target)
            val conditions = if (wifiOnly) {
                DownloadConditions.Builder().requireWifi().build()
            } else {
                DownloadConditions.Builder().build()
            }
            translator.downloadModelIfNeeded(conditions)
                .onSuccessTask { translator.translate(text) }
                .addOnSuccessListener { translated ->
                    result.success(
                        mapOf("text" to translated, "source" to source, "same" to false),
                    )
                }
                .addOnFailureListener { e ->
                    result.error(
                        if (ready) "failed" else "download_failed",
                        e.message,
                        null,
                    )
                }
        }
    }

    private fun translator(source: String, target: String): Translator {
        val key = "$source>$target"
        translators[key]?.let { return it }
        val created = Translation.getClient(
            TranslatorOptions.Builder()
                .setSourceLanguage(source)
                .setTargetLanguage(target)
                .build(),
        )
        translators[key] = created
        while (translators.size > MAX_TRANSLATORS) {
            val eldest = translators.entries.iterator().next()
            translators.remove(eldest.key)
            eldest.value.close()
        }
        return created
    }

    private fun onUnmeteredNetwork(context: Context): Boolean {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager ?: return false
        val network = manager.activeNetwork ?: return false
        val caps = manager.getNetworkCapabilities(network) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }

    private fun models(result: MethodChannel.Result) {
        RemoteModelManager.getInstance()
            .getDownloadedModels(TranslateRemoteModel::class.java)
            .addOnSuccessListener { models ->
                result.success(models.map { it.language }.sorted())
            }
            .addOnFailureListener { result.success(emptyList<String>()) }
    }

    private fun deleteModel(call: MethodCall, result: MethodChannel.Result) {
        val tag = call.argument<String>("language")
        val language = tag?.let { TranslateLanguage.fromLanguageTag(it) }
        if (language == null) {
            result.success(false)
            return
        }
        val iterator = translators.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            val pair = entry.key.split(">")
            if (pair.contains(language)) {
                entry.value.close()
                iterator.remove()
            }
        }
        RemoteModelManager.getInstance()
            .deleteDownloadedModel(TranslateRemoteModel.Builder(language).build())
            .addOnSuccessListener { result.success(true) }
            .addOnFailureListener { result.success(false) }
    }
}
