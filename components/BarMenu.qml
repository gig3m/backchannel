import QtQuick
import qs.Commons

// The right-click menu on the bar glyph. Arrow keys move, Enter picks.
Item {
  id: root
  property var service: null
  signal closeRequested()
  signal showConversations()

  property bool confirmingSignOut: false
  readonly property bool loggedIn: service ? service.loggedIn : false

  readonly property var items: {
    var s = root.service
    var out = [{ id: "window", icon: "󰏌", label: "Open Backchannel" }]
    if (root.loggedIn) {
      out.push({ id: "popup", icon: "󰍡", label: "Show conversations" })
      out.push({ id: "read", icon: "󰄬", label: "Mark all as read", enabled: s && s.unreadTotal > 0 })
    }
    out.push({ sep: true })
    out.push({ id: "click", icon: "󰳽", label: "Click opens: " + (s && s.clickAction === "window" ? "window" : "popup") })
    out.push({ id: "notify", icon: s && s.notificationsEnabled ? "󰂚" : "󰂛", label: "Notifications: " + (s && s.notificationsEnabled ? "on" : "off") })
    out.push({ sep: true })
    out.push({ id: "restart", icon: "󰜉", label: "Restart daemon", enabled: s && s.installed })
    if (root.loggedIn) out.push({ id: "signout", icon: "󰍃", label: root.confirmingSignOut ? "Click again to sign out of " + s.teamName : "Sign out…", danger: root.confirmingSignOut })
    return out
  }

  property int current: 0
  implicitHeight: column.implicitHeight + Style.space(12)
  implicitWidth: Style.space(280)

  function reset() { root.confirmingSignOut = false; root.current = 0 }
  function move(step) {
    var n = root.items.length, i = root.current
    for (var k = 0; k < n; k++) {
      i = (i + step + n) % n
      var it = root.items[i]
      if (!it.sep && it.enabled !== false) { root.current = i; return }
    }
  }

  function activate(it) {
    var s = root.service
    if (!it || it.sep || it.enabled === false || !s) return
    switch (it.id) {
    case "window": s.openWindow(); root.closeRequested(); break
    case "popup": root.showConversations(); break
    case "read": s.markAllRead(); root.closeRequested(); break
    case "click": s.set("clickAction", s.clickAction === "window" ? "popup" : "window"); break
    case "notify": s.set("notifications", !s.notificationsEnabled); break
    case "restart": s.restartDaemon(); root.closeRequested(); break
    case "signout":
      if (!root.confirmingSignOut) { root.confirmingSignOut = true; return }
      root.confirmingSignOut = false
      s.logout(null)
      root.closeRequested()
      break
    }
  }

  focus: true
  Keys.onUpPressed: root.move(-1)
  Keys.onDownPressed: root.move(1)
  Keys.onReturnPressed: root.activate(root.items[root.current])
  Keys.onEnterPressed: root.activate(root.items[root.current])
  Keys.onEscapePressed: root.closeRequested()

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: Style.space(6)

    Repeater {
      model: root.items
      delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property bool enabledItem: modelData.enabled !== false
        width: column.width
        height: modelData.sep ? Style.space(9) : Style.spacing.popupRowHeight

        Rectangle {
          visible: row.modelData.sep === true
          anchors.verticalCenter: parent.verticalCenter
          x: Style.space(10)
          width: parent.width - Style.space(20)
          height: 1
          color: Util.alpha(Color.foreground, 0.12)
        }

        Rectangle {
          visible: !row.modelData.sep
          anchors.fill: parent
          anchors.leftMargin: Style.space(4)
          anchors.rightMargin: Style.space(4)
          color: row.index === root.current && row.enabledItem ? Util.alpha(Color.foreground, 0.08) : "transparent"
          Row {
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(8)
            spacing: Style.space(10)
            Text {
              width: Style.space(16)
              text: row.modelData.icon || ""
              color: row.modelData.danger ? Color.urgent : Color.foreground
              opacity: row.enabledItem ? 1 : 0.4
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Text {
              text: row.modelData.label || ""
              textFormat: Text.PlainText
              color: row.modelData.danger ? Color.urgent : Color.foreground
              opacity: row.enabledItem ? 1 : 0.4
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.enabledItem
            cursorShape: Qt.PointingHandCursor
            onEntered: root.current = row.index
            onClicked: root.activate(row.modelData)
          }
        }
      }
    }
  }
}
