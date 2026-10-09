import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui as Ui

// The sidebar: direct messages by recent activity, then channels by name,
// unread ones in bold with a count. Typing filters; arrows and Enter pick.
// A query also finds people to message, public channels to join and, in
// the window, a full message search.
Item {
  id: root
  property var service: null
  property string selectedId: ""
  property bool compact: false     // the bar popup: only what needs attention
  readonly property bool hasTextFocus: search.activeFocus

  signal picked(string convId)
  signal searchRequested(string query)

  readonly property string query: search.text.trim().toLowerCase()

  readonly property var rows: {
    var all = service ? service.conversations : []
    var q = root.query
    var favs = [], dms = [], chans = []
    for (var i = 0; i < all.length; i++) {
      var c = all[i]
      var direct = c.kind === "dm" || c.kind === "group"
      if (q !== "") { if (String(c.name).toLowerCase().indexOf(q) < 0) continue }
      else if (direct && !c.open) continue
      else if (!direct && (c.unread === 0 || (service && service.isMuted(c.id))) && (root.compact || (service && service.hideQuietChannels)) && !(service && service.isFavourite(c.id) && !root.compact)) continue
      else if (direct && root.compact && c.unread === 0 && dms.length >= 8) continue
      if (service && service.isFavourite(c.id)) favs.push(c)
      else if (direct) dms.push(c); else chans.push(c)
    }
    favs.sort(function(a, b) { return a.name.localeCompare(b.name) })
    dms.sort(function(a, b) { return (b.latest || "").localeCompare(a.latest || "") })
    chans.sort(function(a, b) { return a.name.localeCompare(b.name) })
    var out = []
    for (var f = 0; f < favs.length; f++) out.push({ section: "Favourites", c: favs[f] })
    for (var j = 0; j < dms.length; j++) out.push({ section: "Direct messages", c: dms[j] })
    for (var k = 0; k < chans.length; k++) out.push({ section: "Channels", c: chans[k] })
    if (q === "" || !service) return out

    // People without a DM in the list yet, and channels to join. Rows that
    // are not conversations carry an id with a prefix; activate() acts on it.
    var hasDM = {}
    for (var d = 0; d < dms.length; d++) if (dms[d].kind === "dm") hasDM[dms[d].user_id] = true
    for (var fv = 0; fv < favs.length; fv++) if (favs[fv].kind === "dm") hasDM[favs[fv].user_id] = true
    var ppl = service.people, np = 0
    for (var pi = 0; pi < ppl.length && np < 6; pi++) {
      var p = ppl[pi]
      if (hasDM[p.id]) continue
      var hay = (p.name + " " + (p.real_name || "") + " " + (p.handle || "")).toLowerCase()
      if (hay.indexOf(q) < 0) continue
      out.push({ section: "People", c: { id: "person:" + p.id, name: p.name, kind: "dm", avatar: p.avatar, hint: p.real_name !== p.name ? p.real_name : (p.title || ""), unread: 0, mentions: 0 } })
      np++
    }
    var other = service.otherChannels, nc = 0
    for (var ci = 0; ci < other.length && nc < 6; ci++) {
      var ch = other[ci]
      if (String(ch.name).toLowerCase().indexOf(q) < 0) continue
      out.push({ section: "Join a channel", c: { id: "join:" + ch.id, name: ch.name, kind: "channel", hint: ch.members + (ch.members === 1 ? " member" : " members"), unread: 0, mentions: 0 } })
      nc++
    }
    if (!root.compact) out.push({ section: "Search", c: { id: "search:", name: "Messages with \u201c" + search.text.trim() + "\u201d", kind: "search", unread: 0, mentions: 0 } })
    return out
  }

  // Pick a row: a conversation opens; a person gets a DM, a channel is
  // joined, then it opens; the search row hands the query up.
  property string busy: ""
  function activate(c) {
    var s = root.service
    if (!s || !c || root.busy !== "") return
    var id = String(c.id)
    if (id.indexOf("search:") === 0) { root.searchRequested(search.text.trim()); return }
    var done = function(r) {
      root.busy = ""
      if (!r.ok) { s.toast(r.error || "could not open"); return }
      search.text = ""
      root.picked(r.result.id)
    }
    if (id.indexOf("person:") === 0) { root.busy = id; s.openDM(id.substring(7), done); return }
    if (id.indexOf("join:") === 0) { root.busy = id; s.joinChannel(id.substring(5), done); return }
    root.picked(id)
  }

  function focusSearch() { search.forceActiveFocus() }

  // ---------- right-click ----------

  signal convLeft(string convId)

  function showMenu(c, source, x, y) {
    var s = root.service
    if (!s || !c || String(c.id).indexOf(":") >= 0) return
    var direct = c.kind === "dm" || c.kind === "group"
    var link = s.permalink(c.id, "", "")
    var items = [
      c.unread > 0 ? { id: "read", icon: "󰄬", label: "Mark as read" } : { id: "unread", icon: "󰇮", label: "Mark as unread", enabled: !!c.latest },
      { sep: true },
      { id: "fav", icon: s.isFavourite(c.id) ? "󰓒" : "󰓎", label: s.isFavourite(c.id) ? "Remove from favourites" : "Add to favourites" },
      { id: "mute", icon: s.isMuted(c.id) ? "󰂚" : "󰂛", label: s.isMuted(c.id) ? "Unmute" : "Mute" },
      { sep: true },
      { id: "copy", icon: "󰆏", label: "Copy link", enabled: link !== "" },
      { id: "open", icon: "󰏌", label: "Open in Slack", enabled: link !== "" },
      { sep: true },
      direct ? { id: "close", icon: "󰅖", label: "Close conversation" }
             : { id: "leave", icon: "󰗼", label: "Leave channel…", danger: false, confirm: "Click again to leave #" + c.name }
    ]
    menu.show(source, x, y, items, c)
  }

  function closeMenus() { menu.close() }

  ActionMenu {
    id: menu
    parent: Overlay.overlay
    onTriggered: function(id, c) {
      var s = root.service
      if (!s || !c) return
      switch (id) {
      case "read": if (c.latest) s.markRead(c.id, c.latest); break
      case "unread": s.markUnread(c.id, "", null); break
      case "fav": s.toggleFavourite(c.id); break
      case "mute": s.toggleMute(c.id); break
      case "copy": s.copyText(s.permalink(c.id, "", "")); break
      case "open": s.openUrl(s.permalink(c.id, "", "")); break
      case "close": s.closeConversation(c.id, function(r) { if (!r.ok) s.toast(r.error) }); root.convLeft(c.id); break
      case "leave": s.leaveConversation(c.id, function(r) { if (!r.ok) s.toast(r.error) }); root.convLeft(c.id); break
      }
    }
  }

  Ui.TextField {
    id: search
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space(8)
    placeholderText: "Jump to…"
    Keys.onDownPressed: { list.forceActiveFocus(); list.currentIndex = 0 }
    Keys.onReturnPressed: if (root.rows.length > 0) root.activate(root.rows[0].c)
    onActiveFocusChanged: if (activeFocus && root.service && root.service.people.length === 0) root.service.loadDirectory()
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
    Keys.onReturnPressed: if (currentIndex >= 0 && currentIndex < root.rows.length) root.activate(root.rows[currentIndex].c)
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
      readonly property bool muted: root.service ? root.service.isMuted(c.id) : false
      readonly property bool unread: c.unread > 0 && !muted
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
            text: item.c.kind === "search" ? "󰍉" : item.c.kind === "channel" ? "#" : item.c.kind === "private" ? "󰌾" : item.c.kind === "group" ? "󰡉" : "󰀄"
            color: Util.alpha(Color.foreground, item.unread ? 0.9 : 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
        Text {
          id: nameText
          width: Math.min(implicitWidth, parent.width - Style.space(26))
          anchors.verticalCenter: parent.verticalCenter
          text: item.c.name
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: item.selected ? Color.accent : Util.alpha(Color.foreground, item.unread ? 1.0 : item.muted ? 0.4 : 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: item.unread
        }
        Text {
          visible: !!item.c.hint
          width: Math.max(0, parent.width - Style.space(26) - nameText.width - parent.spacing)
          anchors.verticalCenter: parent.verticalCenter
          text: root.busy === item.c.id ? "…" : (item.c.hint || "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Util.alpha(Color.foreground, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        id: badge
        visible: !item.muted && (item.c.mentions > 0 || (item.unread && (item.c.kind === "dm" || item.c.kind === "group")))
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
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(ev) {
          if (ev.button === Qt.RightButton) root.showMenu(item.c, mouse, ev.x, ev.y)
          else root.activate(item.c)
        }
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
