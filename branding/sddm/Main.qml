import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: Screen.width
  height: Screen.height
  color: "#0b0911"

  function resolveUser() {
    // Resolve at submit time: userModel may not be populated when the file is
    // first evaluated, and a stale property then sends an empty username to
    // SDDM ("user not known to the underlying authentication module").
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
    // Resolve NOW, not from a cached property — an empty username made SDDM
    // log "user not known to the underlying authentication module" and fail
    // the password even though it was correct.
    var user = root.resolveUser()
    if (user.length === 0) {
      errmsg.text = "no user selected — cannot log in"
      errmsg.visible = true
      return
    }
    if (!root.sessionOK) {
      errmsg.text = "cannot find a session — install is broken"
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
    spacing: Math.round(root.height * 0.035)

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(root.width * 0.5, 520)
      height: Math.round(width * 0.545)
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
      text: root.resolveUser()
      color: "#D8D0DC"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: Math.max(18, Math.round(root.height * 0.034))
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Rectangle {
      width: Math.min(root.width * 0.34, 400)
      height: Math.max(50, Math.round(root.height * 0.065))
      radius: 8
      color: "#14111A"
      border.color: root.loginFailed ? "#f7768e" : "#43384C"
      border.width: 1
      anchors.horizontalCenter: parent.horizontalCenter

      Row {
        anchors.centerIn: parent
        spacing: 8
        Repeater {
          model: Math.min(password.text.length, 16)
          Rectangle {
            width: 9
            height: 9
            radius: 4.5
            color: root.loginFailed ? "#f7768e" : "#B6849D"
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

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
        color: "transparent"
        selectionColor: "transparent"
        selectedTextColor: "transparent"
        cursorDelegate: Item {}
        focus: true

        onTextChanged: root.loginFailed = false

        Keys.onPressed: {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.attemptLogin()
            event.accepted = true
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
    // pick the first usable session (niri preferred) and confirm we found one
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var n = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString().toLowerCase()
      if (n.indexOf("niri") !== -1) { root.sessionIndex = i; break }
    }
    root.sessionOK = sessionModel.rowCount() > 0
    password.forceActiveFocus()
  }
}