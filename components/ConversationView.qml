import QtQuick
import QtQuick.Controls
import qs.Commons
import "Format.js" as Format

// A conversation, or one thread of it (threadTs set): the messages, older
// history on scrolling up, live updates from the service, and a composer.
//
// The list runs bottom-to-top with the newest message at index 0, so new
// messages land at the bottom and loading older history never moves what
// is on screen.
Item {
  id: root
  property var service: null
  property string viewId: "view"
  property string convId: ""
  property string threadTs: ""
  property bool compact: false
  property bool active: true       // the view is on screen

  signal openThread(string ts)
  signal closeRequested()

  readonly property var conv: service && convId ? service.conversationById(convId) : null
  readonly property string title: threadTs !== "" ? "Thread" : (service ? service.conversationName(conv) : "")
  readonly property bool hasTextFocus: composer.activeFocus
  property bool loading: false
  property bool loadingOlder: false
  property bool hasMore: false
  property string error: ""
  property string sendError: ""

  ListModel { id: messages }

  // ---------- editing ----------

  property string editingTs: ""
  function startEdit(m) {
    if (!m || !m.own) return
    root.editingTs = m.ts
    composer.text = m.text || ""
    composer.forceActiveFocus()
    composer.cursorPosition = composer.text.length
  }
  function cancelEdit() { root.editingTs = ""; composer.text = "" }
  function editLast() {
    for (var i = 0; i < messages.count; i++) {
      var m = JSON.parse(messages.get(i).json)
      if (m.own && !m.subtype) { root.startEdit(m); return true }
    }
    return false
  }

  // ---------- right-click on a message ----------

  function showMessageMenu(m, index, source, x, y) {
    var s = root.service
    if (!s) return
    var system = !!m.subtype && ["bot_message", "thread_broadcast", "file_share", "me_message"].indexOf(m.subtype) < 0
    var link = s.permalink(root.convId, m.ts, m.thread_ts || "")
    var items = []
    if (!system) items.push({ emojis: [{ n: "+1", e: "👍" }, { n: "white_check_mark", e: "✅" }, { n: "eyes", e: "👀" }, { n: "joy", e: "😂" }, { n: "pray", e: "🙏" }, { n: "tada", e: "🎉" }] })
    if (!system && root.threadTs === "") items.push({ id: "thread", icon: "󰍪", label: (m.reply_count || 0) > 0 ? "Open thread" : "Reply in thread" })
    items.push({ sep: true })
    items.push({ id: "copy", icon: "󰆏", label: "Copy text", enabled: (m.text || "") !== "" })
    items.push({ id: "link", icon: "󰌷", label: "Copy link", enabled: link !== "" })
    items.push({ id: "open", icon: "󰏌", label: "Open in Slack", enabled: link !== "" })
    if (root.threadTs === "") items.push({ id: "unread", icon: "󰇮", label: "Mark unread from here" })
    var files = m.files || []
    if (files.length > 0) {
      items.push({ sep: true })
      for (var i = 0; i < files.length && i < 4; i++) {
        if (files[i].image) items.push({ id: "copyimg:" + i, icon: "󰋩", label: "Copy image" + (files.length > 1 ? " " + (i + 1) : "") })
        items.push({ id: "save:" + i, icon: "󰇚", label: "Save " + files[i].name })
      }
    }
    if (m.own && !system) {
      items.push({ sep: true })
      items.push({ id: "edit", icon: "󰏫", label: "Edit message" })
      items.push({ id: "delete", icon: "󰆴", label: "Delete message…", confirm: "Click again to delete" })
    }
    msgMenu.show(source, x, y, items, { m: m, index: index })
  }

  function closeMenus() { msgMenu.close() }

  ActionMenu {
    id: msgMenu
    parent: Overlay.overlay
    onTriggered: function(id, ctx) {
      var s = root.service, m = ctx.m
      if (!s || !m) return
      if (id.indexOf("react:") === 0) { s.react(root.convId, m.ts, id.substring(6), true, null); return }
      if (id.indexOf("copyimg:") === 0) { s.copyImage(m.files[Number(id.substring(8))].id); return }
      if (id.indexOf("save:") === 0) { var f = m.files[Number(id.substring(5))]; s.saveFile(f.id, f.name); return }
      switch (id) {
      case "thread": root.openThread(m.ts); break
      case "copy": s.copyText(m.text); break
      case "link": s.copyText(s.permalink(root.convId, m.ts, m.thread_ts || "")); break
      case "open": s.openUrl(s.permalink(root.convId, m.ts, m.thread_ts || "")); break
      case "unread": s.markUnread(root.convId, m.ts, function(r) { if (!r.ok) s.toast(r.error) }); root.holdRead = true; break
      case "edit": root.startEdit(m); break
      case "delete": s.deleteMessage(root.convId, m.ts, function(r) { if (!r.ok) s.toast(r.error) }); break
      }
    }
  }

  // After "Mark unread from here" the view must not mark the conversation
  // read again until the user comes back to it.
  property bool holdRead: false
  onHoldReadChanged: publishViewing()

  function open(convId, threadTs) {
    root.convId = convId || ""
    root.threadTs = threadTs || ""
    root.reload()
  }

  function reload() {
    root.holdRead = false
    root.editingTs = ""
    messages.clear()
    root.error = ""
    root.hasMore = false
    root.publishViewing()
    if (!service || !convId) return
    root.loading = true
    var cid = convId, tts = threadTs
    var done = function(r) {
      if (cid !== root.convId || tts !== root.threadTs) return
      root.loading = false
      if (!r.ok) { root.error = r.error || "could not load"; return }
      var list = r.result.messages || []
      // newest first
      for (var i = list.length - 1; i >= 0; i--) messages.append({ ts: list[i].ts, json: JSON.stringify(list[i]) })
      root.hasMore = r.result.has_more === true
      root.markNewest()
    }
    if (threadTs !== "") service.replies(convId, threadTs, done)
    else service.history(convId, "", done)
  }

  function loadOlder() {
    if (root.threadTs !== "" || !root.hasMore || root.loadingOlder || messages.count === 0) return
    root.loadingOlder = true
    var cid = root.convId
    service.history(cid, messages.get(messages.count - 1).ts, function(r) {
      root.loadingOlder = false
      if (cid !== root.convId || !r.ok) return
      var list = r.result.messages || []
      for (var i = list.length - 1; i >= 0; i--) messages.append({ ts: list[i].ts, json: JSON.stringify(list[i]) })
      root.hasMore = r.result.has_more === true
    })
  }

  function markNewest() {
    if (root.holdRead) return
    if (root.active && root.threadTs === "" && messages.count > 0 && service) service.markRead(root.convId, messages.get(0).ts)
  }

  function publishViewing() {
    if (service) service.setViewing(root.viewId, root.active && root.threadTs === "" && !root.holdRead ? root.convId : "")
  }
  onActiveChanged: {
    if (!active) root.holdRead = false
    publishViewing()
    if (active) markNewest()
  }
  Component.onDestruction: if (service) service.setViewing(root.viewId, "")

  function indexOf(ts) {
    for (var i = 0; i < messages.count; i++) if (messages.get(i).ts === ts) return i
    return -1
  }
  function belongsHere(ev) {
    if (ev.conv !== root.convId) return false
    var m = ev.message
    if (root.threadTs !== "") return m.ts === root.threadTs || m.thread_ts === root.threadTs
    return !ev.in_thread
  }

  Connections {
    target: root.service
    function onMessageReceived(ev) {
      if (!root.belongsHere(ev) || root.indexOf(ev.message.ts) >= 0) return
      messages.insert(0, { ts: ev.message.ts, json: JSON.stringify(ev.message) })
      if (list.atYEnd || ev.message.own) list.positionViewAtBeginning()
    }
    function onMessageChanged(ev) {
      if (ev.conv !== root.convId) return
      var i = root.indexOf(ev.message.ts)
      if (i >= 0) messages.setProperty(i, "json", JSON.stringify(ev.message))
    }
    function onMessageDeleted(ev) {
      if (ev.conv !== root.convId) return
      var i = root.indexOf(ev.ts)
      if (i >= 0) messages.remove(i)
    }
    function onReactionChanged(ev) {
      if (ev.conv !== root.convId) return
      var i = root.indexOf(ev.ts)
      if (i < 0) return
      var m = JSON.parse(messages.get(i).json)
      var rs = m.reactions || []
      var found = false
      for (var k = 0; k < rs.length; k++) {
        if (rs[k].name !== ev.name) continue
        found = true
        rs[k].count += ev.added ? 1 : -1
        if (ev.me) rs[k].me = ev.added
        if (rs[k].count <= 0) rs.splice(k, 1)
        break
      }
      if (!found && ev.added) rs.push({ name: ev.name, emoji: ev.emoji, count: 1, me: ev.me === true })
      m.reactions = rs
      messages.setProperty(i, "json", JSON.stringify(m))
    }
  }

  // ---------- header ----------

  Rectangle {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: headerRow.implicitHeight + Style.space(16)
    color: "transparent"
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Util.alpha(Color.foreground, 0.1) }

    Row {
      id: headerRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(10)
      Text {
        id: closeBtn
        visible: root.threadTs !== "" || root.compact
        text: root.threadTs !== "" && !root.compact ? "󰅖" : "󰁍"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        anchors.verticalCenter: parent.verticalCenter
        MouseArea { anchors.fill: parent; anchors.margins: -Style.space(4); cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
      }
      Column {
        width: parent.width - (closeBtn.visible ? closeBtn.width + parent.spacing : 0)
        Text {
          width: parent.width
          text: root.title
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          visible: text !== ""
          width: parent.width
          text: root.threadTs !== "" ? root.service.conversationName(root.conv) : (root.conv && root.conv.topic ? root.conv.topic : "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Util.alpha(Color.foreground, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ---------- messages ----------

  ListView {
    id: list
    anchors.top: header.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: composerBox.top
    anchors.bottomMargin: Style.space(6)
    clip: true
    model: messages
    verticalLayoutDirection: ListView.BottomToTop
    spacing: 0
    cacheBuffer: 2000
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    // Near the top (the far end in this direction): fetch older history.
    onContentYChanged: if (atYBeginning || (visibleArea.yPosition < 0.05 && contentHeight > height)) root.loadOlder()

    delegate: MessageRow {
      required property int index
      required property string json
      width: ListView.view.width
      service: root.service
      convId: root.convId
      inThread: root.threadTs !== ""
      compact: root.compact
      msg: JSON.parse(json)
      // The message above is the next one in the model (older).
      older: index + 1 < messages.count ? JSON.parse(messages.get(index + 1).json) : null
      onOpenThread: function(ts) { root.openThread(ts) }
      onContextRequested: function(source, x, y) { root.showMessageMenu(msg, index, source, x, y) }
    }

    footer: Item {
      width: ListView.view.width
      height: root.loadingOlder ? Style.space(28) : Style.space(4)
      Text {
        visible: root.loadingOlder
        anchors.centerIn: parent
        text: "Loading older messages…"
        color: Util.alpha(Color.foreground, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  Text {
    anchors.centerIn: list
    visible: root.loading || root.error !== "" || (!root.loading && messages.count === 0 && root.convId !== "")
    width: list.width - Style.space(40)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: root.loading ? "Loading…" : root.error !== "" ? root.error : "No messages yet."
    color: root.error !== "" ? Color.urgent : Util.alpha(Color.foreground, 0.5)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  // Drop a file anywhere on the view to upload it here.
  DropArea {
    anchors.fill: parent
    onDropped: function(drop) {
      if (!drop.hasUrls || !root.service) return
      for (var i = 0; i < drop.urls.length; i++) {
        var u = String(drop.urls[i])
        if (u.indexOf("file://") !== 0) continue
        root.service.upload(root.convId, decodeURIComponent(u.substring(7)), "", root.threadTs, function(r) {
          if (!r.ok) root.sendError = r.error || "upload failed"
        })
      }
    }
    Rectangle {
      anchors.fill: parent
      visible: parent.containsDrag
      color: Util.alpha(Color.accent, 0.12)
      border.width: 2
      border.color: Color.accent
      Text { anchors.centerIn: parent; text: "Drop to upload"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.heading }
    }
  }

  // ---------- composer ----------

  Rectangle {
    id: composerBox
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(10)
    height: Math.min(Style.space(160), composer.implicitHeight) + (errorText.visible ? errorText.implicitHeight + Style.space(4) : 0)
    color: Util.alpha(Color.foreground, 0.05)
    border.width: 1
    border.color: root.editingTs !== "" || composer.activeFocus ? Color.accent : Util.alpha(Color.foreground, 0.15)
    visible: root.convId !== ""

    ScrollView {
      id: scroll
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: Math.min(Style.space(160), composer.implicitHeight)
      TextArea {
        id: composer
        wrapMode: TextArea.Wrap
        placeholderText: root.threadTs !== "" ? "Reply…" : "Message " + root.title
        placeholderTextColor: Util.alpha(Color.foreground, 0.4)
        color: Color.foreground
        selectionColor: Util.alpha(Color.accent, 0.35)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        background: null
        padding: Style.space(8)
        Keys.onPressed: function(event) {
          if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
            event.accepted = true
            root.submit()
          } else if (event.key === Qt.Key_Up && composer.text === "" && root.editingTs === "") {
            if (root.editLast()) event.accepted = true
          } else if (event.key === Qt.Key_Escape && root.editingTs !== "") {
            event.accepted = true
            root.cancelEdit()
          } else if (event.key === Qt.Key_Escape && root.threadTs !== "") {
            event.accepted = true
            root.closeRequested()
          }
        }
      }
    }
    Text {
      id: editLabel
      visible: root.editingTs !== ""
      anchors.bottom: parent.top
      anchors.left: parent.left
      anchors.bottomMargin: Style.space(3)
      text: "Editing · Enter to save · Esc to cancel"
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Text {
      id: errorText
      visible: root.sendError !== ""
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.margins: Style.space(6)
      text: root.sendError
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  function submit() {
    var t = composer.text
    if (!service) return
    if (root.editingTs !== "") {
      var ts = root.editingTs
      if (t.trim() === "") return
      root.sendError = ""
      service.edit(root.convId, ts, t, function(r) {
        if (!r.ok) root.sendError = r.error || "not saved"
        else if (root.editingTs === ts) root.cancelEdit()
      })
      return
    }
    if (t.trim() === "") return
    root.sendError = ""
    var keep = t
    composer.text = ""
    service.send(root.convId, t, root.threadTs, function(r) {
      if (!r.ok) { root.sendError = r.error || "not sent"; if (composer.text === "") composer.text = keep }
    })
  }
  function focusComposer() { composer.forceActiveFocus() }
}
