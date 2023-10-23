import QtQuick 2.15
import QtGraphicalEffects 1.15

import QtQuick.Window 2.2
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root
    Image{
        anchors.fill: parent
        source: "images/background.jpg"

    }
    property int stage

    onStageChanged: {
        switch(stage){
        case 1:
            busyIndicator.opacity = 1;
            break;
        case 6:
            busyIndicator.opacity = 0;
            break;
        }
    }

    Item {
        id: content
        anchors.fill: parent
        TextMetrics {
            id: units
            text: "M"
            property int gridUnit: boundingRect.height
            property int largeSpacing: units.gridUnit
            property int smallSpacing: Math.max(2, gridUnit/4)
        }
        Column{
            property real maxWidth: units.gridUnit * 13
            width: maxWidth
            id: central
            anchors.centerIn: parent
            spacing: 20
            Image {
                id: logo
                //match SDDM/lockscreen avatar positioning
                property real size: units.gridUnit * 8

                source: "images/archlinux-logo.svg"
                width: maxWidth

                sourceSize.width: 254
                sourceSize.height: 85
                layer.enabled: true
                layer.effect: DropShadow {
                    transparentBorder: true
                    horizontalOffset: 1
                    verticalOffset: 1
                    radius: 3
                }
            }
            Item{
                height:PlasmaCore.Units.gridUnit/3
                width: parent.width * .8
                anchors.horizontalCenter: parent.horizontalCenter
                Rectangle{
                    color: "#ffffff"
                    anchors.left: parent.left
                    height: parent.height
                    width: (parent.width / 6) * (stage - 1)

                    radius: height

                    layer.enabled: true
                    layer.effect: DropShadow {
                        transparentBorder: true
                        horizontalOffset: 1
                        verticalOffset: 1
                        radius: 3
                    }
                    Behavior on width{
                        NumberAnimation {
                            easing: Easing.InOutQuad
                        }
                    }
                }
            }
        }
        Image {
            y: parent.height - (parent.height - central.y) / 2 - height / 2
            id: busyIndicator

            source: "images/busy.svgz"
            sourceSize.height: units.gridUnit * 2.5
            sourceSize.width: units.gridUnit * 2.5
            anchors.horizontalCenter: parent.horizontalCenter

            opacity: 0.0

            layer.enabled: true
            layer.effect: DropShadow {
                id: busyShadow
                transparentBorder: true
                horizontalOffset: 0
                verticalOffset: 0
                radius: 4
                RotationAnimator on rotation {
                    id: rotationAnimator
                    from: 0
                    to: 360
                    duration: 2000
                    loops: Animation.Infinite
                }
            }
            Behavior on opacity {
                NumberAnimation{
                    duration: 1000
                    easing.type: Easing.InOutQuad
                }
            }
        }
        Row {
            spacing: PlasmaCore.Units.smallSpacing*2
            anchors {
                bottom: parent.bottom
                right: parent.right
                margins: PlasmaCore.Units.gridUnit
            }
            Text {
                color: "#eff0f1"
                // Work around Qt bug where NativeRendering breaks for non-integer scale factors
                // https://bugreports.qt.io/browse/QTBUG-67007
                renderType: Screen.devicePixelRatio % 1 !== 0 ? Text.QtRendering : Text.NativeRendering
                anchors.verticalCenter: parent.verticalCenter
                text: i18ndc("plasma_lookandfeel_org.kde.lookandfeel", "This is the first text the user sees while starting in the splash screen, should be translated as something short, is a form that can be seen on a product. Plasma is the project name so shouldn't be translated.", "Plasma made by KDE")
            }
        }
    }
}
