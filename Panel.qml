import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components"

// Backchannel in the bar: the glyph with the unread count, and the popup
// under it. Session state lives in Service.qml, shared with the window.
Panel {
  id: root
  moduleName: "gig3m.backchannel"
  ipcTarget: "gig3m.backchannel"
  manageIpc: false

  readonly property var service: (bar && bar.shell && typeof bar.shell.serviceFor === "function")
    ? bar.shell.serviceFor("gig3m.backchannel") : null
  readonly property bool loggedIn: service ? service.loggedIn : false
  readonly property int unreadTotal: service ? service.unreadTotal : 0
  readonly property int mentionTotal: service ? service.mentionTotal : 0
  readonly property string glyph: service ? service.glyph : "󰒱"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened && service) service.ensureDaemon()

  // Scripts and keybindings:
  //   omarchy-shell gig3m.backchannel toggle
  //   omarchy-shell gig3m.backchannel status
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function app(): void { if (root.service) root.service.openWindow() }
    function status(): string {
      var s = root.service
      return JSON.stringify({
        installed: s ? s.installed : false, connected: s ? s.connected : false, loggedIn: root.loggedIn,
        team: s ? s.teamName : "", live: s ? s.status.connected === true : false,
        unread: root.unreadTotal, mentions: root.mentionTotal, conversations: s ? s.conversations.length : 0
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.mentionTotal > 0 ? root.glyph + " " + root.mentionTotal : root.glyph
    dimmed: !root.loggedIn || root.unreadTotal === 0
    tooltipText: "Backchannel: " + (root.service ? root.service.stateText : "starting")
      + (root.mentionTotal > 0 ? " · " + root.mentionTotal + " for you" : "")
      + (root.unreadTotal > 0 ? " · " + root.unreadTotal + " unread" : "")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) { if (root.service) root.service.openWindow() }
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: body.hasTextFocus
      onCloseRequested: { if (!body.handleClose()) root.close() }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      PopupContent {
        id: body
        width: parent.width
        height: parent.height
        service: root.service
        bar: root.bar
        opened: root.opened
        onCloseRequested: root.close()
      }
    }
  }
}
