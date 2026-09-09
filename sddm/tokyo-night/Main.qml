// ~/dotfiles/sddm/tokyo-night/Main.qml — gestionado desde ~/dotfiles
// Tema de SDDM a juego con el resto del escritorio (Hyprland/Waybar/hyprlock/
// wlogout, todos en paleta Tokyo Night). Ver ~/dotfiles/hypr/.config/hypr/
// hyprlock.conf y ~/dotfiles/waybar/.config/waybar/style.css para los mismos
// colores/estructura (isla flotante translúcida, reloj grande, acentos azul/
// violeta).

import QtQuick 2.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: 1920
    height: 1080

    LayoutMirroring.enabled: Qt.locale().textDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    // Paleta Tokyo Night (idéntica a hyprlock.conf / waybar/style.css)
    property color bg0: "#16161e"
    property color bg1: "#1a1b26"
    property color panelBg: Qt.rgba(26 / 255, 27 / 255, 38 / 255, 0.85)
    property color panelBorder: Qt.rgba(122 / 255, 162 / 255, 247 / 255, 0.3)
    property color buttonBg: Qt.rgba(41 / 255, 46 / 255, 66 / 255, 0.75)
    property color buttonBorder: "#292e42"
    property color blue: "#7aa2f7"
    property color purple: "#bb9af7"
    property color green: "#9ece6a"
    property color red: "#f7768e"
    property color orange: "#e0af68"
    property color fg: "#c0caf5"
    property color fg2: "#a9b1d6"
    property color comment: "#545c7e"
    property string uiFont: "CaskaydiaCove Nerd Font"

    property int sessionIndex: sessionCombo.index

    TextConstants { id: textConstants }

    gradient: Gradient {
        GradientStop { position: 0.0; color: root.bg1 }
        GradientStop { position: 1.0; color: root.bg0 }
    }

    QtObject {
        id: clockModel
        property date now: new Date()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: clockModel.now = new Date()
    }

    Connections {
        target: sddm
        onLoginSucceeded: {
            errorMessage.color = root.green
            errorMessage.text = textConstants.loginSucceeded
        }
        onLoginFailed: {
            password.text = ""
            errorMessage.color = root.red
            errorMessage.text = textConstants.loginFailed
        }
        onInformationMessage: {
            errorMessage.color = root.orange
            errorMessage.text = message
        }
    }

    // Barra superior estilo Waybar (isla flotante translúcida)
    Rectangle {
        id: topBar
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 16
        width: topRow.implicitWidth + 36
        height: 36
        radius: 14
        color: root.panelBg
        border.color: root.panelBorder
        border.width: 1

        Row {
            id: topRow
            anchors.centerIn: parent
            spacing: 16

            Text {
                text: "❄ " + (sddm.hostName || "Arch Linux")
                color: root.blue
                font.family: root.uiFont
                font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                color: root.fg2
                font.family: root.uiFont
                font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(clockModel.now, "dddd, d MMMM yyyy")
            }
        }
    }

    // Reloj + tarjeta de login, centrados (mismo layout que hyprlock.conf)
    Column {
        id: mainColumn
        anchors.centerIn: parent
        spacing: 18

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clockModel.now, "hh:mm")
            color: root.fg
            font.family: root.uiFont
            font.pixelSize: 96
            font.bold: true
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            width: 380
            height: cardColumn.implicitHeight + 48
            radius: 18
            color: root.panelBg
            border.color: root.panelBorder
            border.width: 1

            Column {
                id: cardColumn
                anchors.centerIn: parent
                width: parent.width - 64
                spacing: 14

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰀄"
                    color: root.blue
                    font.family: root.uiFont
                    font.pixelSize: 42
                }

                TextBox {
                    id: name
                    width: parent.width
                    height: 42
                    text: userModel.lastUser
                    color: Qt.rgba(1, 1, 1, 0.04)
                    textColor: root.fg
                    borderColor: root.comment
                    focusColor: root.blue
                    hoverColor: root.purple
                    radius: 12
                    font.family: root.uiFont
                    font.pixelSize: 15

                    KeyNavigation.backtab: loginButton
                    KeyNavigation.tab: password

                    Keys.onPressed: {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sddm.login(name.text, password.text, sessionIndex)
                            event.accepted = true
                        }
                    }
                }

                PasswordBox {
                    id: password
                    width: parent.width
                    height: 42
                    color: Qt.rgba(1, 1, 1, 0.04)
                    textColor: root.fg
                    borderColor: root.comment
                    focusColor: root.purple
                    hoverColor: root.blue
                    radius: 12
                    font.family: root.uiFont
                    font.pixelSize: 15

                    KeyNavigation.backtab: name
                    KeyNavigation.tab: sessionCombo

                    Keys.onPressed: {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sddm.login(name.text, password.text, sessionIndex)
                            event.accepted = true
                        }
                    }
                }

                ComboBox {
                    id: sessionCombo
                    width: parent.width
                    height: 38
                    model: sessionModel
                    index: sessionModel.lastIndex
                    color: Qt.rgba(1, 1, 1, 0.04)
                    textColor: root.fg2
                    borderColor: root.comment
                    focusColor: root.blue
                    hoverColor: root.purple
                    menuColor: root.bg1
                    arrowColor: "transparent"
                    font.family: root.uiFont
                    font.pixelSize: 13

                    KeyNavigation.backtab: password
                    KeyNavigation.tab: loginButton

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "▾"
                        color: root.fg2
                        font.pixelSize: 14
                    }
                }

                Text {
                    id: errorMessage
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: textConstants.prompt
                    color: root.fg2
                    font.family: root.uiFont
                    font.pixelSize: 12
                }

                Button {
                    id: loginButton
                    width: parent.width
                    height: 42
                    radius: 12
                    text: textConstants.login
                    color: root.blue
                    activeColor: root.purple
                    pressedColor: "#5a7bc7"
                    textColor: root.bg0
                    font.family: root.uiFont
                    font.bold: true

                    onClicked: sddm.login(name.text, password.text, sessionIndex)

                    KeyNavigation.backtab: sessionCombo
                    KeyNavigation.tab: name
                }
            }
        }
    }

    // Botones de energía, estilo wlogout (mismos colores/bordes/hover)
    Row {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 30
        spacing: 20

        Repeater {
            model: [
                { glyph: "⏾", action: "suspend", visible: sddm.canSuspend },
                { glyph: "↻", action: "reboot", visible: sddm.canReboot },
                { glyph: "⏻", action: "poweroff", visible: sddm.canPowerOff }
            ]

            delegate: Rectangle {
                width: 54
                height: 54
                radius: 16
                visible: modelData.visible
                color: powerMouse.containsMouse ? Qt.rgba(122 / 255, 162 / 255, 247 / 255, 0.25) : root.buttonBg
                border.color: powerMouse.containsMouse ? root.blue : root.buttonBorder
                border.width: 2

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: modelData.glyph
                    color: root.fg
                    font.family: root.uiFont
                    font.pixelSize: 22
                }

                MouseArea {
                    id: powerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.action === "suspend") sddm.suspend()
                        else if (modelData.action === "reboot") sddm.reboot()
                        else sddm.powerOff()
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        if (name.text === "")
            name.focus = true
        else
            password.focus = true
    }
}
