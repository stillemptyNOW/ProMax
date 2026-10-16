package io.github.stillemptynow.promax

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.util.Log
import java.io.File

object IncomingUris {

    private const val TAG = "IncomingUris"
    private const val SHARE_PROVIDER_SUFFIX = ".flutter.share_provider"

    fun isAcceptable(context: Context, uri: Uri): Boolean {
        val accepted = when (uri.scheme) {
            ContentResolver.SCHEME_CONTENT -> !isPrivateProvider(context, uri)
            ContentResolver.SCHEME_FILE -> isSharedStorageFile(uri)
            else -> false
        }
        if (!accepted) Log.w(TAG, "rejected ${uri.scheme}://${uri.authority.orEmpty()}")
        return accepted
    }

    private fun isPrivateProvider(context: Context, uri: Uri): Boolean {
        val authority = uri.authority ?: return true
        val ownPackage = context.packageName
        if (authority == ownPackage + SHARE_PROVIDER_SUFFIX) return false
        if (authority == ownPackage || authority.startsWith("$ownPackage.")) return true
        val provider = try {
            context.packageManager.resolveContentProvider(authority, 0)
        } catch (e: Exception) {
            null
        }
        return provider?.packageName == ownPackage
    }

    private fun isSharedStorageFile(uri: Uri): Boolean {
        val path = uri.path ?: return false
        return try {
            val file = File(path).canonicalFile
            @Suppress("DEPRECATION")
            val shared = Environment.getExternalStorageDirectory().canonicalFile
            val prefix = shared.path + File.separator
            if (!file.path.startsWith(prefix)) return false
            val topLevel = file.path.substring(prefix.length).substringBefore(File.separatorChar)
            !topLevel.equals("Android", ignoreCase = true)
        } catch (e: Exception) {
            false
        }
    }
}
