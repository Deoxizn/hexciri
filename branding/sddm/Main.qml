import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: Screen.width
  height: Screen.height
  color: root.bgColor

  // Theme wallpaper (staged per theme-set as background.<ext> beside this
  // file). Missing/unreadable → renders nothing and the base color above
  // carries the screen, i.e. the classic static look.
  Image {
    anchors.fill: parent
    source: root.bgFile.length > 0 ? root.bgFile : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
  }
  // Readability dim over bright wallpapers (same static look when absent).
  Rectangle {
    anchors.fill: parent
    visible: root.bgFile.length > 0
    color: "#000000"
    opacity: 0.45
  }

  // Design canvas is 640x790 and never scales above 1x, so on big panels
  // (2880x1920 here) everything renders at true pixel size; smaller panels
  // scale the canvas down proportionally to fit.
  property real scaleFactor: Math.min(1, root.width / 640, root.height / 790)
  property string currentUser: {
    if (config.Username && config.Username.length > 0) return config.Username
    return userModel.lastUser
  }
  // install.sh stamps theme.conf with Fingerprint=true only when a reader was
  // detected at deploy time. Auto-starting the login with an empty password
  // is only safe with a reader to claim it; on a readerless (or not yet
  // set-up) box that empty submit fails red — or sits in fprintd's timeout
  // looking stuck — before the user can type. So the default is OFF: a
  // missing key means type-your-password, and only an explicit stamped
  // Fingerprint=true enables touch-to-login.
  property bool hasFingerprint: config.Fingerprint === "true"
  // WM-aware default session (stamped per-box by hexciri-sync as
  // PreferredSession=<niri|hyprland> from ~/.config/hexciri/wm):
  // pinned WM first, then SDDM's remembered last session, then any known
  // compositor. A hardcoded niri default would drag a Hyprland box back
  // into niri whenever both sessions are installed.
  // Live theme-follow (written per theme-set by hexciri-sddm-apply into
  // theme.conf): wallpaper file + palette. Absent keys fall back to the
  // static hexciri look, so an old theme.conf still renders fine.
  property string bgColor: (config.Background && config.Background.length > 0) ? config.Background : "#0b0911"
  property string mutedColor: (config.Muted && config.Muted.length > 0) ? config.Muted : "#b6849d"
  property string errorColor: (config.Error && config.Error.length > 0) ? config.Error : "#f7768e"
  property string bgFile: (config.BackgroundFile && config.BackgroundFile.length > 0) ? config.BackgroundFile : ""
  property string preferredSession: {
    if (config.PreferredSession && config.PreferredSession.length > 0) return config.PreferredSession
    return ""
  }
  property int sessionIndex: {
    if (root.preferredSession.length > 0) {
      for (var i = 0; i < sessionModel.rowCount(); i++) {
        var pname = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString().toLowerCase()
        if (pname.indexOf(root.preferredSession.toLowerCase()) !== -1)
          return i
      }
    }
    if (sessionModel.lastIndex >= 0 && sessionModel.lastIndex < sessionModel.rowCount())
      return sessionModel.lastIndex
    for (var j = 0; j < sessionModel.rowCount(); j++) {
      var name = (sessionModel.data(sessionModel.index(j, 0), Qt.DisplayRole) || "").toString().toLowerCase()
      if (name.indexOf("niri") !== -1 || name.indexOf("hyprland") !== -1 || name.indexOf("uwsm") !== -1)
        return j
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
        visible: root.bgFile.length === 0
        source: "logo.png"
        width: Math.min(sourceSize.width, 716)
        height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
        fillMode: Image.PreserveAspectFit
        anchors.horizontalCenter: parent.horizontalCenter
      }

      // Login cluster on a dim pill: once a wallpaper is staged the bare
      // lock + entry wash out, so they sit on a mostly-transparent black
      // box and render larger than the original static look.
      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: loginRow.width + 56
        height: loginRow.height + 44

        Rectangle {
          anchors.fill: parent
          color: "#000000"
          opacity: 0.5
          radius: 20
        }

      Row {
        id: loginRow
        anchors.centerIn: parent
        spacing: 18

        Image {
          source: root.errText.length > 0 ? "lock-failed.png" : "lock.png"
          width: 46
          height: 52
          fillMode: Image.PreserveAspectFit
          anchors.verticalCenter: parent.verticalCenter
        }

        Item {
          width: entry.width
          height: entry.height

          Image {
            id: entry
            source: root.errText.length > 0 ? "entry-failed.png" : "entry.png"
            width: 200
            height: 34
            anchors.centerIn: parent
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
              model: Math.min(password.text.length, 21)

              Image {
                source: "bullet.png"
                width: 8
                height: 8
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
            font.letterSpacing: 3
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
      }

      Text {
        visible: root.infoText.length > 0 || root.errText.length > 0
        text: root.errText.length > 0 ? root.errText : root.infoText
        color: root.errText.length > 0 ? root.errorColor : root.mutedColor
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 16
        anchors.horizontalCenter: parent.horizontalCenter
      }
    }
  }

  // Fingerprint-first: when a reader exists, start authentication as soon as
  // the greeter is up so fprintd claims the reader and prompts immediately (no
  // password needed). /etc/pam.d/sddm tries pam_unix first, so a typed
  // password succeeds at once while this empty submit falls through to fprintd
  // for touch-to-login. Without a reader this timer sits idle — the password
  // field already has focus and login is driven by the user's first Enter.
  // NOTE (pam_fprintd(8) LIMITATIONS): SDDM is a single serial PAM
  // conversation, so fingerprint-first ordering would block typed passwords
  // behind fprintd's timeout and look stuck on a dying reader. Never put
  // pam_fprintd before pam_unix in the sddm stack.
  Timer {
    id: autoStart
    interval: 1000
    repeat: false
    onTriggered: {
      if (root.hasFingerprint && root.currentUser.length > 0) {
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