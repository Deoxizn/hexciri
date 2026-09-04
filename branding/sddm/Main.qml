import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#0b0911"

  property string currentUser: userModel.lastUser
  property bool loginFailed: false
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString().toLowerCase()
      if (name.indexOf("niri") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  function attemptLogin() {
    sddm.login(root.currentUser, password.text, root.sessionIndex)
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

  Text {
    anchors.top: parent.top
    anchors.topMargin: 30
    anchors.horizontalCenter: parent.horizontalCenter
    color: "#6B5E72"
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: 22
    text: Qt.formatDateTime(new Date(), "HH:mm")
  }

  Column {
    anchors.centerIn: parent
    spacing: 22

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, 280)
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
      text: "H E X C I R I"
      color: "#B6849D"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 26
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
      text: root.currentUser
      color: "#D8D0DC"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 18
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Rectangle {
      width: 300
      height: 46
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
      visible: root.loginFailed
      text: "authentication failed"
      color: "#f7768e"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 14
      anchors.horizontalCenter: parent.horizontalCenter
    }
  }

  Component.onCompleted: password.forceActiveFocus()
}
