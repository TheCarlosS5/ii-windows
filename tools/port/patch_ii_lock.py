"""Lock screen on Windows (audit 2026-10-09, P2, option A): Windows' lock screen stays the only
secure one, with ii's look around it. Locking from ii plays ii's lock animation (blurred, zoomed
wallpaper) before Windows locks; a lock Windows does by itself (Win+L, idle, lid) puts ii in its
locked state underneath; unlocking leaves it with ii's animation. Before this, nothing reset
ii's state after Windows unlocked. Exact-match edits of the staged tree."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

ROOT = os.environ.get('II_STAGE_DIR') or os.path.join(os.path.dirname(__file__), '..', '..', 'build', 'ii')


def path(*parts):
    return os.path.join(ROOT, *parts)


edit(path('modules', 'common', 'panels', 'lock', 'LockScreen.qml'), [
    ('''    WlSessionLock {
        id: lock
        locked: GlobalStates.screenLocked
        surface: root.sessionLockSurface
    }''',
     '''    WlSessionLock {
        id: lock
        locked: GlobalStates.screenLocked
        surface: root.sessionLockSurface
        // ii-windows: Windows' own lock screen follows and leads ii's locked state. `secure` is
        // Windows' word that the session is locked; GlobalStates.screenLocked is only ii's look.
        onWindowsLocked: GlobalStates.screenLocked = true
        onWindowsUnlocked: GlobalStates.screenLocked = false
        // The lock call failed, or Windows never confirmed it: ii must not keep presenting a
        // lock that is not there.
        onLockFailed: reason => {
            console.warn("[lock] Windows did not lock the session: " + reason);
            GlobalStates.screenLocked = false;
        }
        // Started inside an already locked session.
        Component.onCompleted: if (lock.secure) GlobalStates.screenLocked = true
    }'''),
])

# Lock.qml moves Hyprland workspaces through hyprctl around a lock: nothing to do on Windows.
edit(path('modules', 'ii', 'lock', 'Lock.qml'), [
    ('''        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                // Lock: save workspace per monitor''',
     '''        function onScreenLockedChanged() {
            return; // ii-windows: no Hyprland workspaces to move
            if (GlobalStates.screenLocked) {
                // Lock: save workspace per monitor'''),
])
