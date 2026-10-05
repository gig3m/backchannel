import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui as Ui

// Everything before a session: the daemon missing or stopped, then the
// three steps of making a Slack app and pasting its two tokens.
Item {
  id: root
  property var service: null
  readonly property bool hasTextFocus: appToken.activeFocus || userToken.activeFocus
  property string error: ""
  property bool busy: false

  implicitHeight: column.implicitHeight + Style.space(48)

  function focusFirst() { if (service && service.connected) appToken.forceActiveFocus() }
  function clearSecrets() { appToken.text = ""; userToken.text = "" }

  component Para: Text {
    width: parent ? parent.width : 0
    wrapMode: Text.Wrap
    textFormat: Text.StyledText
    color: Util.alpha(Color.foreground, 0.8)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    linkColor: Color.accent
    onLinkActivated: function(link) { if (root.service) root.service.openUrl(link) }
  }
  component Step: Text {
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  Column {
    id: column
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(48), Style.space(520))
    spacing: Style.space(14)

    Row {
      spacing: Style.space(14)
      Text { text: root.service ? root.service.glyph : "󰒱"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.display; anchors.verticalCenter: parent.verticalCenter }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        Text { text: "Backchannel"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
        Text { text: root.service ? root.service.stateText : ""; color: Util.alpha(Color.foreground, 0.6); font.family: Style.font.family; font.pixelSize: Style.font.caption }
      }
    }

    // ---- no daemon ----
    Column {
      visible: root.service && root.service.checked && !root.service.installed
      width: parent.width
      spacing: Style.space(10)
      Para { text: "Backchannel talks to Slack through a small daemon, <b>backchanneld</b>, which holds your tokens so the shell never sees them. Install it, then come back here:" }
      Rectangle {
        width: parent.width; height: cmd.implicitHeight + Style.space(16)
        color: Util.alpha(Color.foreground, 0.06)
        TextEdit { id: cmd; anchors.fill: parent; anchors.margins: Style.space(8); readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body
          text: "yay -S backchanneld-bin\nsystemctl --user enable --now backchanneld" }
      }
      Ui.Button { text: "Check again"; bordered: true; onClicked: root.service.checkInstalled() }
    }

    // ---- daemon stopped ----
    Column {
      visible: root.service && root.service.installed && !root.service.connected
      width: parent.width
      spacing: Style.space(10)
      Para { text: "The daemon is installed but not running." }
      Ui.Button { text: root.service && root.service.starting ? "Starting…" : "Start backchanneld"; bordered: true; onClicked: { root.service.starting = false; root.service.ensureDaemon() } }
    }

    // ---- sign in ----
    Column {
      visible: root.service && root.service.connected && !root.service.loggedIn
      width: parent.width
      spacing: Style.space(10)

      Para { text: "Backchannel signs in through a Slack app that you create in your own workspace, so your messages go only between your computer and Slack. It takes about two minutes." }

      Step { text: "1. Create the app" }
      Para { text: "This opens Slack with the app's settings filled in. Pick your workspace and press <b>Create</b>." }
      Ui.Button { text: "Create the Slack app  󰏌"; bordered: true; onClicked: root.service.openCreateApp() }

      Step { text: "2. Make an app token" }
      Para { text: "In the app's <b>Basic Information</b>, under <b>App-Level Tokens</b>, press <b>Generate Token and Scopes</b>, add the <b>connections:write</b> scope, and copy the token (it starts with xapp-)." }
      Ui.TextField { id: appToken; width: parent.width; password: true; placeholderText: "xapp-…"; onAccepted: userToken.forceActiveFocus() }

      Step { text: "3. Install it to your workspace" }
      Para { text: "Under <b>Install App</b>, press <b>Install to Workspace</b> and allow it. Copy the <b>User OAuth Token</b> (it starts with xoxp-). If your workspace needs an admin to approve apps, they will be asked first." }
      Ui.TextField { id: userToken; width: parent.width; password: true; placeholderText: "xoxp-…"; onAccepted: root.connect() }

      Text {
        visible: root.error !== "" || !!(root.service && root.service.status.error)
        width: parent.width
        wrapMode: Text.Wrap
        text: root.error !== "" ? root.error : (root.service ? root.service.status.error || "" : "")
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Ui.Button { text: root.busy ? "Connecting…" : "Connect"; bordered: true; onClicked: root.connect() }
      Para { text: "Tokens are kept by the daemon in ~/.local/state/backchanneld, readable only by you. Sign out from the window's menu to remove them." }
    }
  }

  function connect() {
    if (root.busy || !root.service) return
    root.error = ""
    root.busy = true
    root.service.setup(userToken.text, appToken.text, function(r) {
      root.busy = false
      if (r.ok) root.clearSecrets()
      else root.error = r.error || "could not connect"
    })
  }
}
