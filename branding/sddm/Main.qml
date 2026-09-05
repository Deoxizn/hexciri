import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: Screen.width
  height: Screen.height
  color: "#0b0911"

  property bool loginFailed: false
  property int sessionIndex: 0
  // The installer stamps Username= into theme.conf, so on single-user installs
  // there is a guaranteed known user: greet a password-only box and submit it
  // automatically. Only multi-user / unknown-user installs fall back to an
  // editable username field.
  property bool passwordOnly: (config.Username || "").length > 0

  function defaultUser() {
    var conf = config.Username || ""
    if (conf.length > 0) return conf
    var last = userModel.lastUser || ""
    if (last.length > 0) return last
    for (var i = 0; i < userModel.rowCount(); i++) {
      var u = (userModel.data(userModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (u !== "root" && u !== "nobody" && u !== "systemd-coredump")
        return u
    }
    return ""
  }

  function attemptLogin() {
    var user = root.passwordOnly ? config.Username : username.text
    if (user.length === 0) {
      errmsg.text = "no username entered"
      errmsg.visible = true
      return
    }
    sddm.login(user, password.text, root.sessionIndex)
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.focus = true
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: Math.round(root.height * 0.028)

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(root.width * 0.5, 520)
      height: Math.round(width * 0.545)
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Row {
      spacing: Math.round(root.height * 0.015)
      anchors.horizontalCenter: parent.horizontalCenter

      Rectangle {
        width: Math.min(root.width * 0.34, 320)
        height: Math.max(46, Math.round(root.height * 0.06))
        radius: 8
        color: "#14111A"
        border.color: "#43384C"
        border.width: 1
        visible: !root.passwordOnly

        TextInput {
          id: username
          anchors.fill: parent
          anchors.leftMargin: 16
          anchors.rightMargin: 16
          verticalAlignment: TextInput.AlignVCenter
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 20
          color: "#D8D0DC"
          text: root.defaultUser()
          selectionColor: "#43384C"
          focus: !root.passwordOnly

          Keys.onPressed: {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down ||
                event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.attemptLogin()
                event.accepted = true
              } else {
                password.forceActiveFocus()
                event.accepted = true
              }
            }
          }
        }
      }

      Rectangle {
        width: root.passwordOnly ? Math.min(root.width * 0.45, 380) : Math.min(root.width * 0.34, 320)
        height: Math.max(46, Math.round(root.height * 0.06))
        radius: 8
        color: "#14111A"
        border.color: root.loginFailed ? "#f7768e" : "#43384C"
        border.width: 1

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 16
          anchors.rightMargin: 16
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 20
          passwordCharacter: "\u2022"
          color: "#D8D0DC"
          selectionColor: "#43384C"
          selectedTextColor: "#D8D0DC"
          focus: root.passwordOnly

          onTextChanged: root.loginFailed = false

          Keys.onPressed: {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.attemptLogin()
              event.accepted = true
            }
          }
        }
      }
    }

    Text {
      id: errmsg
      visible: root.loginFailed
      text: "authentication failed"
      color: "#f7768e"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: Math.max(14, Math.round(root.height * 0.026))
      anchors.horizontalCenter: parent.horizontalCenter
    }
  }

  Component.onCompleted: {
    username.text = root.defaultUser()
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var n = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString().toLowerCase()
      if (n.indexOf("niri") !== -1) { root.sessionIndex = i; break }
      root.sessionIndex = i
    }
  }
}