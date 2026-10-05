package com.sanogueralorenzo.androidsteam

import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.games.SteamAppInfo
import com.sanogueralorenzo.androidsteam.library.SteamLibrary
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LibraryDataTest {
    @Test fun metadataAndInstalledFilesNeverGrantLicensesAndAccountsStayIsolated() {
        val original = InstrumentationRegistry.getInstrumentation().targetContext
        val source = File(original.filesDir, "home/.local/share/Steam/appcache/appinfo.vdf")
        assumeTrue(source.isFile)
        // Reuse only public product metadata; all account/configuration data below is synthetic.
        val temporary = File.createTempFile("library-data-", "", original.cacheDir).apply { delete(); mkdir() }
        val context = object : ContextWrapper(original) { override fun getFilesDir() = temporary }
        val root = File(temporary, "home/.local/share/Steam")
        fun write(path: String, text: String) = File(root, path).apply { parentFile!!.mkdirs(); writeText(text) }
        try {
            val metadata = File(root, "appcache/appinfo.vdf").apply { parentFile!!.mkdirs(); source.copyTo(this) }
            val candidates = SteamAppInfo.games(metadata).values.filter { !it.visibleOnlyWhenInstalled }.take(2)
            require(candidates.size == 2)
            val owned = candidates[0].appId
            val unowned = candidates[1].appId
            write("config/loginusers.vdf", "\"users\" { \"76561197960265729\" {} }")
            write("userdata/1/config/localconfig.vdf", "\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { \"$owned\" { \"Playtime\" \"12\" } } } } } }")
            write("steamapps/appmanifest_$unowned.acf", "\"AppState\" { \"StateFlags\" \"4\" \"SizeOnDisk\" \"50\" }")
            val licenses = File(temporary, "library/1.json").apply { parentFile!!.mkdirs() }
            fun license(ids: List<Int>, account: String = "1") {
                licenses.writeText(JSONObject().put("account", account).put("checked", 1).put("available", JSONArray(ids)).toString())
            }
            license(listOf(owned))
            val library = SteamLibrary(context)
            assertEquals(listOf(owned), library.read().games.map { it.appId })
            assertEquals(12L, library.read().games.single().playtimeMinutes)
            assertFalse(library.read().games.single().installed)
            val download = write("steamapps/appmanifest_$owned.acf", "\"AppState\" { \"StateFlags\" \"1026\" \"BytesDownloaded\" \"30\" \"BytesToDownload\" \"100\" }")
            library.read().games.single().let { game ->
                assertTrue(game.pending); assertFalse(game.installed)
                assertEquals(30L, game.downloaded); assertEquals(100L, game.downloadTotal)
            }
            download.writeText("\"AppState\" { \"StateFlags\" \"260\" }")
            library.read().games.single().let { game -> assertTrue(game.installed); assertFalse(game.pending) }
            download.delete()
            fun hidden(added: List<Int>, removed: List<Int>) = JSONArray().put(JSONArray().put("user-collections.hidden")
                .put(JSONObject().put("value", JSONObject().put("added", JSONArray(added)).put("removed", JSONArray(removed)).toString()))).toString()
            write("userdata/1/config/cloudstorage/cloud-storage-namespace-1.json", hidden(listOf(owned), emptyList()))
            assertTrue(library.read().games.isEmpty())
            write("userdata/1/config/cloudstorage/cloud-storage-namespace-1.modified.json", hidden(emptyList(), listOf(owned)))
            assertEquals(listOf(owned), library.read().games.map { it.appId })
            val visible = SteamAppInfo.games(metadata).values.firstOrNull { it.visibleOnlyWhenInstalled }
            if (visible != null) {
                license(listOf(visible.appId))
                assertTrue(library.read().games.isEmpty())
                write("steamapps/appmanifest_${visible.appId}.acf", "\"AppState\" { \"StateFlags\" \"4\" }")
                assertEquals(visible.appId, library.read().games.single().appId)
            }
            license(listOf(owned), "2")
            assertThrows(IllegalArgumentException::class.java) { library.read() }
            license(listOf(owned))
            write("config/loginusers.vdf", "\"users\" { \"76561197960265730\" {} }")
            write("userdata/2/config/localconfig.vdf", "\"UserLocalConfigStore\" {}")
            assertThrows(IllegalArgumentException::class.java) { library.read() }
        } finally { temporary.deleteRecursively() }
    }
}
