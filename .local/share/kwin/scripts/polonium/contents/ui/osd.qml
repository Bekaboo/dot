// osd.qml - On screen display for various stuff

import QtQuick;
import QtQuick.Layouts;
import org.kde.kwin;
import org.kde.plasma.components as PC3;
import org.kde.plasma.core as PlasmaCore;
import org.kde.kirigami as Kirigami;

PlasmaCore.Dialog {
    id: osd;

    property rect screenGeometry;

    function show(text) {
        // Abort any previous timers
        hideTimer.stop();
        // Update current screen information
        this.screenGeometry = Workspace.clientArea(KWin.FullScreenArea, Workspace.activeScreen, Workspace.currentDesktop);
        // Set the text
        main.text = text;
        // Show the popup
        this.visible = true;
        // Start popup hide timer
        hideTimer.interval = 1000;
        hideTimer.restart();
    }

    type: PlasmaCore.Dialog.OnScreenDisplay;
    flags: Qt.Popup | Qt.WindowStaysOnTopHint;
    location: PlasmaCore.Types.Floating;
    outputOnly: true;
    x: (screenGeometry.x + screenGeometry.width / 2) - width / 2;
    y: (screenGeometry.y + screenGeometry.height * 2 / 3) - height / 2;
    visible: false;

    mainItem: PC3.Label {
        id: main;
        Layout.minimumWidth: Math.max(main.implicitWidth, Kirigami.Units.gridUnit * 10);
        Layout.minimumHeight: Kirigami.Units.gridUnit * 1.35;
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2;
        horizontalAlignment: Text.AlignHCenter;

        // Hides the popup window when triggered
        Timer {
            id: hideTimer;
            repeat: false;
            
            onTriggered: osd.visible = false;
        }
    }

}
