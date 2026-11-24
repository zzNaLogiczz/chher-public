package com.chhreader.chh_app

import android.app.Activity
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class AccountsBridge(activity: Activity, engine: FlutterEngine) {
    private val vault = AccountVault.get(activity)
    private val checker = AccountChecker.get(activity)
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chh/accounts")
    private val changed: () -> Unit = { channel.invokeMethod("changed", null) }

    init {
        vault.listeners.add(changed)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "check") {
                try {
                    val uids = call.argument<List<*>>("uids")?.map {
                        if (it !is String || !it.matches(UID)) throw AccountVault.Failure("invalid_arguments")
                        it
                    }?.toSet()?.takeIf { it.isNotEmpty() }
                    val force = call.argument<Boolean>("force") == true
                    checker.check(uids, force) { _, failure ->
                        if (failure != null) {
                            replyError(result, failure)
                        } else {
                            vault.submit { respond(result) { vault.list() } }
                        }
                    }
                } catch (error: Exception) {
                    replyError(result, error)
                }
                return@setMethodCallHandler
            }

            vault.submit {
                respond(result) {
                    when (call.method) {
                        "list" -> vault.list()
                        "save" -> vault.capture(
                            call.uid()!!,
                            call.argument<String>("name")?.takeIf { it.isNotBlank() }
                                ?: throw AccountVault.Failure("invalid_arguments"),
                            call.count("notices"),
                            call.count("messages"),
                            call.argument<Boolean>("observed") == true,
                        )
                        "activate" -> vault.activate(call.uid()!!)
                        "remove" -> vault.remove(call.uid()!!)
                        "markExpired" -> vault.markExpired(call.uid()!!)
                        "beginLogin" -> vault.beginLogin(call.uid(optional = true))
                        "peekAuth" -> vault.peekAuth()
                        "endLogin" -> vault.endLogin(call.argument<Boolean>("restore")
                            ?: throw AccountVault.Failure("invalid_arguments"))
                        "recover" -> vault.recover()
                        else -> {
                            main.post { result.notImplemented() }
                            return@submit
                        }
                    }
                }
            }
        }
    }

    private inline fun respond(result: MethodChannel.Result, block: () -> Any?) {
        try {
            val response = block()
            main.post { result.success(response) }
        } catch (error: Exception) {
            replyError(result, error)
        }
    }

    private fun MethodCall.uid(optional: Boolean = false): String? {
        val uid = argument<String>("uid")
        if (optional && uid == null) return null
        return uid?.takeIf { it.matches(UID) } ?: throw AccountVault.Failure("invalid_arguments")
    }

    private fun MethodCall.count(key: String): Int? =
        argument<Int>(key)?.also { if (it < 0) throw AccountVault.Failure("invalid_arguments") }

    private fun replyError(result: MethodChannel.Result, error: Exception) {
        // Android/JSON exceptions may contain cookie contents. Only send stable codes.
        val code = when (error) {
            is AccountVault.Failure -> error.code
            is ClassCastException -> "invalid_arguments"
            else -> "vault_unavailable"
        }
        main.post { result.error(code, null, null) }
    }

    fun dispose() {
        vault.listeners.remove(changed)
        channel.setMethodCallHandler(null)
    }

    companion object {
        private val UID = Regex("[1-9][0-9]*")
    }
}
