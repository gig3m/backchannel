import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui as Ui

// The sidebar: direct messages by recent activity, then channels by name,
// unread ones in bold with a count. Typing filters; arrows and Enter pick.
Item {
  id: root
  property var service: null
  property string selectedId: ""
  property bool compact: false     // the bar popup: only what needs attention
  readonly property bool hasTextFocus: search.activeFocus

  signal picked(string convId)

  readonly property string query: search.text.trim().toLowerCase()

  readonly property var rows: {
    var all = service ? service.conversations : []
    var q = root.query
    var dms = [], chans = []
    for (var i = 0; i < all.length; i++) {
      var c = all[i]
      var direct = c.kind === "dm" || c.kind === "group"
      if (q !== "") { if (String(c.name).toLowerCase().indexOf(q) < 0) continue }
      else if (direct && !c.open) continue
      else if (!direct && c.unread === 0 && (root.compact || (service && service.hideQuietChannels))) continue
      else if (direct && root.compact && c.unread === 0 && dms.length >= 8) continue
      if (direct) dms.push(c); else chans.push(c)
    }
    dms.sort(function(a, b) { return (b.latest || "").localeCompare(a.latest || "") })
    chans.sort(function(a, b) { return a.name.localeCompare(b.name) })
    var out = []
    for (var j = 0; j < dms.length; j++) out.push({ section: "Direct messages", c: dms[j] })
    for (var k = 0; k < chans.length; k++) out.push({ section: "Channels", c: chans[k] })
    return out
  }

  function focusSearch() { search.forceActiveFocus() }

  Ui.TextField {
    id: search
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space(8)
    placeholderText: "Jump to…"
    Keys.onDownPressed: { list.forceActiveFocus(); list.currentIndex = 0 }
    Keys.onReturnPressed: if (root.rows.length > 0) root.picked(root.rows[0].c.id)
    Keys.onEscapePressed: function(event) { if (text !== "") { text = ""; event.accepted = true } else event.accepted = false }
  }

  ListView {
    id: list
    anchors.top: search.bottom
    anchors.topMargin: Style.space(4)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    model: root.rows
    keyNavigationEnabled: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    Keys.onReturnPressed: if (currentIndex >= 0 && currentIndex < root.rows.length) root.picked(root.rows[currentIndex].c.id)
    Keys.onUpPressed: function(event) { if (currentIndex <= 0) search.forceActiveFocus(); else event.accepted = false }

    delegate: Column {
      id: entry
      required property var modelData
      required property int index
      width: ListView.view.width
      readonly property bool firstOfSection: index === 0 || root.rows[index - 1].section !== modelData.section
      Text {
        visible: entry.firstOfSection
        width: parent.width
        text: entry.modelData.section
        leftPadding: Style.space(12)
        topPadding: Style.space(10)
        bottomPadding: Style.space(4)
        color: Util.alpha(Color.foreground, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    Rectangle {
      id: item
      readonly property var c: entry.modelData.c
      readonly property bool selected: c.id === root.selectedId
      readonly property bool unread: c.unread > 0
      width: parent.width
      height: Style.space(30)
      color: selected ? Util.alpha(Color.accent, 0.18)
        : (entry.ListView.isCurrentItem && list.activeFocus) || mouse.containsMouse ? Util.alpha(Color.foreground, 0.06) : "transparent"

      Row {
        anchors.left: parent.left
        anchors.right: badge.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(6)
        spacing: Style.space(8)
        Item {
          width: Style.space(18); height: Style.space(18)
          anchors.verticalCenter: parent.verticalCenter
          Image {
            anchors.fill: parent
            visible: !!(item.c.kind === "dm" && item.c.avatar && root.service && root.service.showAvatars)
            source: visible ? item.c.avatar || "" : ""
            sourceSize.width: 36; sourceSize.height: 36
            asynchronous: true
          }
          Text {
            anchors.centerIn: parent
            visible: !(item.c.kind === "dm" && item.c.avatar && root.service && root.service.showAvatars)
            text: item.c.kind === "channel" ? "#" : item.c.kind === "private" ? "󰌾" : item.c.kind === "group" ? "󰡉" : "󰀄"
            color: Util.alpha(Color.foreground, item.unread ? 0.9 : 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
        Text {
          width: parent.width - Style.space(26)
          anchors.verticalCenter: parent.verticalCenter
          text: item.c.name
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: item.selected ? Color.accent : Util.alpha(Color.foreground, item.unread ? 1.0 : 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: item.unread
        }
      }

      Rectangle {
        id: badge
        visible: item.c.mentions > 0 || (item.unread && (item.c.kind === "dm" || item.c.kind === "group"))
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? Math.max(height, badgeText.implicitWidth + Style.space(8)) : 0
        height: Style.space(16)
        radius: height / 2
        color: Color.urgent
        Text {
          id: badgeText
          anchors.centerIn: parent
          text: Math.max(item.c.mentions, item.c.unread) > 99 ? "99+" : String(Math.max(item.c.mentions, item.c.unread))
          color: Color.background
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked(item.c.id)
      }
    }
    }
  }

  Text {
    anchors.centerIn: list
    visible: root.rows.length === 0
    width: list.width - Style.space(24)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: root.query !== "" ? "Nothing matches." : root.compact ? "All caught up." : (root.service && root.service.status.loading ? "Loading…" : "No conversations.")
    color: Util.alpha(Color.foreground, 0.5)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}
