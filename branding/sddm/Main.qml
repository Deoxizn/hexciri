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
  // Which SDDM session to log into. Order: the hexciri-configured WM first
  // (theme.conf "Session=", written by hexciri-session-set / install /
  // hexciri-sync), then the legacy niri/uwsm default, then the newest session
  // file. The switcher below reassigns it for this login only.
  property int sessionIndex: {
    var want = (config.Session || "").toString().toLowerCase()
    var picked = -1
    var fallback = -1
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (picked < 0 && want.length > 0 && name.toLowerCase().indexOf(want) !== -1)
        picked = i
      if (fallback < 0 && (name.indexOf("niri") !== -1 || name.indexOf("uwsm") !== -1))
        fallback = i
    }
    if (picked >= 0) return picked
    if (fallback >= 0) return fallback
    return sessionModel.lastIndex
  }

  property bool multiSession: sessionModel.rowCount() > 1
  property string sessionName: {
    var s = root.sessionIndex
    if (s >= 0 && s < sessionModel.rowCount())
      return (sessionModel.data(sessionModel.index(s, 0), Qt.DisplayRole) || "").toString()
    return ""
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

      // Session switcher — shown only when the box has more than one WM
      // installed (the hexciri theme used to hardcode niri, which meant it
      // could never boot into a swapped-in mango/hyprland/sway).
      ComboBox {
        id: sessionCombo
        visible: root.multiSession
        width: 160
        height: 26
        anchors.horizontalCenter: parent.horizontalCenter
        model: sessionModel
        index: root.sessionIndex
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 13
        color: "#151020"
        menuColor: "#151020"
        borderColor: "#3b2b52"
        textColor: "#d7c6e8"
        hoverColor: "#5a3d85"
        arrowColor: "#b6849d"
        onValueChanged: {
          root.sessionIndex = id
          root.errText = ""
          root.infoText = ""
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
  // Only auto-runs when there is a single session — once a session switcher
  // exists the user must pick one (and press Enter) so the choice is theirs.
  Timer {
    id: autoStart
    interval: 1000
    repeat: false
    onTriggered: {
      if (root.currentUser.length > 0 && !root.multiSession) {
        root.infoText = "touch the reader or enter your password"
        sddm.login(root.currentUser, "", root.sessionIndex)
      }
    }
  }

  Component.onCompleted: {
    password.forceActiveFocus()
    if (root.multiSession && root.sessionName.length > 0)
      root.infoText = "session: " + root.sessionName + " — pick one, then touch the reader or enter your password"
    autoStart.start()
  }
}