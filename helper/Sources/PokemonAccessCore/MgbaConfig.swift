/// The private mGBA configuration the launcher writes: no FPS counter in the
/// window title (it fights the screen reader), game audio at half volume so
/// speech stays audible, no pause when focus moves to a dialog, and the
/// default keyboard bindings pinned (X = A, Z = B, A = L, S = R, Return =
/// Start, Backspace = Select, arrows = D-pad). Values live in the `ports.qt`
/// section, which mGBA consults before its root settings.
public struct MgbaConfig: Equatable {
    public var volume: Int

    public init(volume: Int = 128) {
        self.volume = volume
    }

    public var ini: String {
        """
        [ports.qt]
        showFps=0
        showOSD=0
        volume=\(volume)
        pauseOnFocusLost=0
        pauseOnMinimize=0
        fullscreen=0
        width=480
        height=320

        [gba.input.QT_K]
        keyA=88
        keyB=90
        keyL=65
        keyR=83
        keyStart=16777220
        keySelect=16777219
        keyUp=16777235
        keyDown=16777237
        keyLeft=16777234
        keyRight=16777236

        """
    }
}
