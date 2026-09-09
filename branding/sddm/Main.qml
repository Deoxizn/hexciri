import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: Screen.width
  height: Screen.height
  color: "#0b0911"

  // Design canvas is 640x790 and never scales above 1x, so on big panels
  // (2880x1920 here) everything renders at true pixel size; smaller panels
  // scale the canvas down proportionally to fit.
  property real scaleFactor: Math.min(1, root.width / 640, root.height / 790)
  property string currentUser: {
    if (config.Username && config.Username.length > 0) return config.Username
    return userModel.lastUser
  }
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("niri") !== -1 || name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  property string infoText: ""
  property string errText: ""

  Connections {
    target: sddm
    function onLoginFailed() {
      root.errText = "authentication failed"
      root.infoText = ""
      password.text = ""
      password.focus = true
      messageReset.start()
    }
    function onLoginSucceeded() {
      root.errText = ""
      root.infoText = ""
    }
    function onInformationMessage(message) {
      if (message && message.length > 0) {
        root.infoText = message
        root.errText = ""
      }
    }
  }

  // Auto-clears the red error banner a few seconds after a failed attempt.
  Timer {
    id: messageReset
    interval: 4000
    onTriggered: root.errText = ""
  }

  Item {
    id: stage
    width: 640
    height: 790
    anchors.centerIn: parent
    transform: Scale {
      xScale: root.scaleFactor
      yScale: root.scaleFactor
      origin.x: 320
      origin.y: 395
    }

    Column {
      anchors.centerIn: parent
      spacing: 40

      Image {
        id: logo
        source: "logo.png"
        width: Math.min(sourceSize.width, 716)
        height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
        fillMode: Image.PreserveAspectFit
        anchors.horizontalCenter: parent.horizontalCenter
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 15

        Image {
          source: root.errText.length > 0 ? "lock-failed.png" : "lock.png"
          width: 34
          height: 38
          fillMode: Image.PreserveAspectFit
          anchors.verticalCenter: parent.verticalCenter
        }

        Item {
          width: entry.width
          height: entry.height

          Image {
            id: entry
            source: root.errText.length > 0 ? "entry-failed.png" : "entry.png"
            width: 150
            height: 26
            anchors.centerIn: parent
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Repeater {
              model: Math.min(password.text.length, 21)

              Image {
                source: "bullet.png"
                width: 6
                height: 6
              }
            }
          }

          TextInput {
            id: password
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.Password
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 17
            font.letterSpacing: 2
            passwordCharacter: "\u2022"
            color: "transparent"
            selectionColor: "transparent"
            selectedTextColor: "transparent"
            cursorDelegate: Item {}
            focus: true

            onTextChanged: {
              root.errText = ""
              root.infoText = ""
            }

            Keys.onPressed: {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.infoText = ""
                sddm.login(root.currentUser, password.text, root.sessionIndex)
                event.accepted = true
              }
            }
          }
        }
      }

      Text {
        visible: root.infoText.length > 0 || root.errText.length > 0
        text: root.errText.length > 0 ? root.errText : root.infoText
        color: root.errText.length > 0 ? "#f7768e" : "#b6849d"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 16
        anchors.horizontalCenter: parent.horizontalCenter
      }
    }
  }

  // Fingerprint-first: start authentication as soon as the greeter is up so
  // fprintd claims the reader and prompts immediately (no password needed).
  // If fprintd is slow, the first attempt fails with a brief red flash and
  // the reader stays armed for the next touch; Enter falls back to password.
  Timer {
    id: autoStart
    interval: 1000
    repeat: false
    onTriggered: {
      if (root.currentUser.length > 0) {
        root.infoText = "touch the reader or enter your password"
        sddm.login(root.currentUser, "", root.sessionIndex)
      }
    }
  }

  Component.onCompleted: {
    password.forceActiveFocus()
    autoStart.start()
  }
}