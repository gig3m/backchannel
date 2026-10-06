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

  // Right-click opens the popup as a menu; every other way in shows the
  // conversations.
  property bool menuMode: false
  onOpenedChanged: {
    if (opened && service) service.ensureDaemon()
    if (!opened) menuMode = false
  }
  function openMenu() {
    if (root.opened && root.menuMode) { root.close(); return }
    root.menuMode = true
    if (!root.opened) root.open()
  }
  function openPopup() {
    if (root.opened && !root.menuMode) { root.close(); return }
    root.menuMode = false
    if (!root.opened) root.open()
  }

  // Scripts and keybindings:
  //   omarchy-shell gig3m.backchannel toggle
  //   omarchy-shell gig3m.backchannel status
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.openPopup() }
    function menu(): void { root.openMenu() }
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
    // Dim only when Backchannel can't work (signed out, daemon down); turn
    // the bar's urgent color when a DM or mention is waiting.
    dimmed: !root.loggedIn
    active: root.mentionTotal > 0
    tooltipText: "Backchannel: " + (root.service ? root.service.stateText : "starting")
      + (root.mentionTotal > 0 ? " · " + root.mentionTotal + " for you" : "")
      + (root.unreadTotal > 0 ? " · " + root.unreadTotal + " unread" : "")
    // Left click does what the setting says; middle click the other one.
    onPressed: function(b) {
      if (b === Qt.RightButton) { root.openMenu(); return }
      var windowFirst = root.service && root.service.clickAction === "window"
      if ((b === Qt.MiddleButton) === windowFirst) root.openPopup()
      else { root.close(); if (root.service) root.service.openWindow() }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.menuMode ? Style.space(280) : Style.space(420))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: body.hasTextFocus || root.menuMode
      onCloseRequested: { if (!body.handleClose()) root.close() }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      PopupContent {
        id: body
        width: parent.width
        height: parent.height
        service: root.service
        bar: root.bar
        opened: root.opened
        menuMode: root.menuMode
        onCloseRequested: root.close()
        onShowConversations: root.menuMode = false
      }
    }
  }
}
