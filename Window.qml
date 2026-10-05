import QtQuick
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "components"

// Backchannel as an app: a real window Hyprland tiles like any other, the
// sidebar on the left, the conversation in the middle, a thread on the
// right when one is open. Same Service.qml as the bar popup.
//
//   omarchy-shell shell summon gig3m.backchannel '{}'                  # open
//   omarchy-shell shell summon gig3m.backchannel '{"conv":"C0123"}'    # open a conversation
//   omarchy-shell shell hide gig3m.backchannel                         # close
Item {
  id: root
  property var shell: null
  property var service: null
  property bool closingFromHost: false
  readonly property bool loggedIn: service ? service.loggedIn : false
  readonly property bool opened: window.visible

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    if (service) service.ensureDaemon()
    var p = null
    try { p = payloadJson ? JSON.parse(String(payloadJson)) : null } catch (e) { p = null }
    Qt.callLater(function() {
      if (p && typeof p.conv === "string" && p.conv !== "") {
        root.openConversation(p.conv)
        if (typeof p.thread === "string" && p.thread !== "") thread.open(p.conv, p.thread)
      }
      if (!root.loggedIn) setup.focusFirst()
      else if (main.convId !== "") main.focusComposer()
      else sidebar.focusSearch()
    })
  }
  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }
  function openConversation(id) {
    if (thread.convId !== id) thread.convId = ""
    main.open(id, "")
    sidebar.selectedId = id
    Qt.callLater(main.focusComposer)
  }

  FloatingWindow {
    id: window
    // FloatingWindow starts visible; the shell decides when it shows.
    visible: false
    title: main.convId !== "" ? main.title + " – Backchannel" : "Backchannel"
    color: Color.background
    implicitWidth: 1100
    implicitHeight: 720
    minimumSize: Qt.size(640, 420)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide(root.service ? root.service.pluginId : "gig3m.backchannel")
      if (!visible) { setup.clearSecrets(); sidebar.closeMenus(); main.closeMenus(); thread.closeMenus() }
    }

    SetupView {
      id: setup
      anchors.fill: parent
      visible: !root.loggedIn
      service: root.service
    }

    Item {
      anchors.fill: parent
      visible: root.loggedIn
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) { sidebar.focusSearch(); event.accepted = true }
      }

      // ---- sidebar ----
      Rectangle {
        id: side
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: Style.space(260)
        color: Util.alpha(Color.foreground, 0.03)
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Util.alpha(Color.foreground, 0.1) }

        Rectangle {
          id: team
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: teamRow.implicitHeight + Style.space(18)
          color: "transparent"
          Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Util.alpha(Color.foreground, 0.1) }
          Row {
            id: teamRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(8)
            Text {
              width: parent.width - signOut.width - parent.spacing - dot.width - parent.spacing
              text: root.service ? root.service.teamName : ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            // Live-link indicator: green when Socket Mode is up.
            Rectangle {
              id: dot
              width: Style.space(8); height: width; radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: root.service && root.service.status.connected ? "#5faf5f" : Color.urgent
              Ui.PanelToolTip { visible: dotMouse.containsMouse; text: root.service ? root.service.stateText : "" }
              MouseArea { id: dotMouse; anchors.fill: parent; hoverEnabled: true }
            }
            Text {
              id: signOut
              text: "󰍃"
              color: Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              anchors.verticalCenter: parent.verticalCenter
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: confirmSignOut.visible = true }
            }
          }
        }

        ConversationList {
          id: sidebar
          anchors.top: team.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          service: root.service
          onPicked: function(id) { root.openConversation(id) }
          onConvLeft: function(id) { if (main.convId === id) { main.open("", ""); thread.convId = ""; sidebar.selectedId = "" } }
        }
      }

      // ---- conversation ----
      ConversationView {
        id: main
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: side.right
        anchors.right: thread.visible ? thread.left : parent.right
        service: root.service
        viewId: "window"
        active: window.visible
        onOpenThread: function(ts) { thread.open(main.convId, ts); Qt.callLater(thread.focusComposer) }
      }
      Text {
        anchors.centerIn: main
        visible: main.convId === ""
        text: "Pick a conversation, or press Ctrl+K."
        color: Util.alpha(Color.foreground, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      // ---- thread ----
      ConversationView {
        id: thread
        visible: convId !== "" && threadTs !== ""
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Math.max(Style.space(320), parent.width * 0.3)
        service: root.service
        viewId: "window-thread"
        active: window.visible && visible
        onCloseRequested: { thread.convId = ""; thread.threadTs = ""; main.focusComposer() }
        Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Util.alpha(Color.foreground, 0.1) }
      }

      // ---- sign-out confirmation ----
      Rectangle {
        id: confirmSignOut
        visible: false
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.85)
        MouseArea { anchors.fill: parent; onClicked: confirmSignOut.visible = false }
        Column {
          anchors.centerIn: parent
          spacing: Style.space(12)
          Text { text: "Sign out of " + (root.service ? root.service.teamName : "") + "?"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
          Text { text: "The daemon forgets both tokens. Your Slack app stays; paste its tokens again to sign back in."; color: Util.alpha(Color.foreground, 0.7); font.family: Style.font.family; font.pixelSize: Style.font.body }
          Row {
            spacing: Style.space(8)
            Ui.Button { text: "Sign out"; bordered: true; onClicked: { confirmSignOut.visible = false; main.open("", ""); thread.convId = ""; root.service.logout(null) } }
            Ui.Button { text: "Cancel"; onClicked: confirmSignOut.visible = false }
          }
        }
      }
    }
  }
}
