// ~/dotfiles/sddm/tokyo-night/Main.qml — gestionado desde ~/dotfiles
// Tema de SDDM a juego con el resto del escritorio (Hyprland/Waybar/hyprlock/
// wlogout, todos en paleta Tokyo Night). Calcado del look de la pantalla de
// bloqueo (ver ~/dotfiles/hypr/.config/hypr/hyprlock.conf): sin tarjeta ni
// barra superior, reloj grande flotante, fecha debajo, campos tipo "pill"
// translúcidos con borde degradado azul/violeta, sin caja contenedora.

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
    property color fieldFill: Qt.rgba(26 / 255, 27 / 255, 38 / 255, 0.6)
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

    // Escala responsive: el tema fue diseñado sobre 2560x1440 (2K). SDDM
    // redimensiona este Rectangle a la resolución real de cada pantalla, pero
    // los tamaños de abajo son píxeles fijos -- sin este factor, en 1920x1080
    // (u otra resolución menor) todo se ve desproporcionadamente grande.
    readonly property real uiScale: Math.min(width / 2560, height / 1440)
    function px(value) { return Math.round(value * uiScale) }

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

    // Reloj + fecha + campos, centrados (mismo layout que hyprlock.conf: sin
    // tarjeta, todo flotando sobre el fondo)
    Column {
        id: mainColumn
        anchors.centerIn: parent
        spacing: root.px(16)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clockModel.now, "hh:mm")
            color: root.fg
            font.family: root.uiFont
            font.pixelSize: root.px(110)
            font.bold: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(clockModel.now, "dddd, d MMMM")
            color: root.fg2
            font.family: root.uiFont
            font.pixelSize: root.px(22)
        }

        Item { width: 1; height: root.px(10) }

        // Campo de usuario: pill translúcida con borde degradado azul/violeta
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.px(300)
            height: root.px(52)

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.blue }
                    GradientStop { position: 1.0; color: root.purple }
                }
            }

            TextBox {
                id: name
                anchors.fill: parent
                anchors.margins: root.px(3)
                text: userModel.lastUser
                color: root.fieldFill
                textColor: root.fg
                borderColor: "transparent"
                focusColor: "transparent"
                hoverColor: "transparent"
                radius: height / 2
                font.family: root.uiFont
                font.pixelSize: root.px(15)

                KeyNavigation.backtab: password
                KeyNavigation.tab: password

                Keys.onPressed: {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        sddm.login(name.text, password.text, sessionIndex)
                        event.accepted = true
                    }
                }
            }
        }

        // Campo de contraseña: misma pill, con botón de envío circular embebido
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.px(300)
            height: root.px(52)

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.blue }
                    GradientStop { position: 1.0; color: root.purple }
                }
            }

            PasswordBox {
                id: password
                anchors.fill: parent
                anchors.margins: root.px(3)
                anchors.rightMargin: root.px(46)
                text: ""
                color: root.fieldFill
                textColor: root.fg
                borderColor: "transparent"
                focusColor: "transparent"
                hoverColor: "transparent"
                radius: height / 2
                font.family: root.uiFont
                font.pixelSize: root.px(15)

                KeyNavigation.backtab: name
                KeyNavigation.tab: sessionCombo

                Keys.onPressed: {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        sddm.login(name.text, password.text, sessionIndex)
                        event.accepted = true
                    }
                }
            }

            Rectangle {
                id: loginButton
                width: root.px(40)
                height: root.px(40)
                radius: width / 2
                anchors.right: parent.right
                anchors.rightMargin: root.px(6)
                anchors.verticalCenter: parent.verticalCenter
                color: loginMouse.containsMouse ? root.purple : root.blue

                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "→"
                    color: root.bg0
                    font.family: root.uiFont
                    font.bold: true
                    font.pixelSize: root.px(18)
                }

                MouseArea {
                    id: loginMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sddm.login(name.text, password.text, sessionIndex)
                }
            }
        }

        // Selector de sesión: discreto, sin borde ni caja (auxiliar, no está
        // en hyprlock porque ahí no aplica)
        ComboBox {
            id: sessionCombo
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.px(180)
            height: root.px(30)
            model: sessionModel
            index: sessionModel.lastIndex
            color: "transparent"
            textColor: root.fg2
            borderColor: "transparent"
            focusColor: "transparent"
            hoverColor: "transparent"
            menuColor: root.bg1
            arrowColor: "transparent"
            font.family: root.uiFont
            font.pixelSize: root.px(12)

            KeyNavigation.backtab: password
            KeyNavigation.tab: name

            Text {
                anchors.right: parent.right
                anchors.rightMargin: root.px(8)
                anchors.verticalCenter: parent.verticalCenter
                text: "▾"
                color: root.fg2
                font.pixelSize: root.px(11)
            }
        }

        Text {
            id: errorMessage
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.px(300)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: textConstants.prompt
            color: root.fg2
            font.family: root.uiFont
            font.pixelSize: root.px(12)
        }
    }

    // Botones de energía, estilo wlogout (mismos colores/bordes/hover)
    Row {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: root.px(30)
        spacing: root.px(20)

        Repeater {
            model: [
                { glyph: "⏾", action: "suspend", visible: sddm.canSuspend },
                { glyph: "↻", action: "reboot", visible: sddm.canReboot },
                { glyph: "⏻", action: "poweroff", visible: sddm.canPowerOff }
            ]

            delegate: Rectangle {
                width: root.px(54)
                height: root.px(54)
                radius: root.px(16)
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
                    font.pixelSize: root.px(22)
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
