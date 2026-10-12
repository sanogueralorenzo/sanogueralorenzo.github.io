package com.sanogueralorenzo.amarchy

import android.app.Activity
import android.os.Bundle
import com.sanogueralorenzo.amarchy.home.HomeScreen
import com.sanogueralorenzo.amarchy.session.WorkspaceService
import com.sanogueralorenzo.amarchy.session.WorkspaceState

class MainActivity : Activity() {
    private val workspace get() = (application as AmarchyApplication).workspace
    private lateinit var screen: HomeScreen
    private val observer: (WorkspaceState) -> Unit = { screen.render(it) }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        screen = HomeScreen(this, { WorkspaceService.open(this) }, { workspace.stop() })
        setContentView(screen)
    }
    override fun onStart() { super.onStart(); workspace.observe(observer) }
    override fun onStop() { workspace.remove(observer); super.onStop() }
}
