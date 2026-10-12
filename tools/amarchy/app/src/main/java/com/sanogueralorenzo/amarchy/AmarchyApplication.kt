package com.sanogueralorenzo.amarchy

import android.app.Application
import com.sanogueralorenzo.amarchy.session.WorkspaceController

class AmarchyApplication : Application() {
    internal val workspace by lazy { WorkspaceController(this) }
}
