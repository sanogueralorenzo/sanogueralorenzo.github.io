package com.sanogueralorenzo.androidsteam.login

import java.util.Base64
import org.json.JSONObject

/** Deliberately not a data class: generated toString/copy methods must not expose tokens. */
internal class SteamTokens(val account: String, val steamId: String, val refresh: String, val guard: String?) {
    companion object {
        fun fromNative(account: String, refresh: String, guard: String?): SteamTokens {
            try {
                check(refresh.length <= 16_384)
                val parts = refresh.split('.')
                check(parts.size == 3)
                val claims = JSONObject(String(Base64.getUrlDecoder().decode(parts[1]), Charsets.UTF_8))
                val audiences = claims.getJSONArray("aud")
                val audience = (0 until audiences.length()).map { audiences.getString(it) }
                check("client" in audience && "derive" in audience)
                check(claims.getLong("exp") > System.currentTimeMillis() / 1000)
                val id = claims.getString("sub")
                check(id.length == 17 && id.all(Char::isDigit))
                // Claims are only a compatibility check. The CM session must authenticate them.
                return SteamTokens(account, id, refresh, guard)
            } catch (_: Exception) {
                error("Steam did not provide a usable client token. Sign in again.")
            }
        }
    }
}
