import qs
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import qs.services
import QtQuick

// ii-windows (plan 2026-10-31, F4): Windows' energy saver in the quick settings.
AndroidQuickToggleButton {
    toggleModel: EnergySaverToggle {}
}
