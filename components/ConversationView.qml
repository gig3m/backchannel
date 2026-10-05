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

  function open(convId, threadTs) {
    root.convId = convId || ""
    root.threadTs = threadTs || ""
    root.reload()
  }

  function reload() {
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
    if (root.active && root.threadTs === "" && messages.count > 0 && service) service.markRead(root.convId, messages.get(0).ts)
  }

  function publishViewing() {
    if (service) service.setViewing(root.viewId, root.active && root.threadTs === "" ? root.convId : "")
  }
  onActiveChanged: { publishViewing(); if (active) markNewest() }
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
    border.color: composer.activeFocus ? Color.accent : Util.alpha(Color.foreground, 0.15)
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
          } else if (event.key === Qt.Key_Escape && root.threadTs !== "") {
            event.accepted = true
            root.closeRequested()
          }
        }
      }
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
    if (t.trim() === "" || !service) return
    root.sendError = ""
    var keep = t
    composer.text = ""
    service.send(root.convId, t, root.threadTs, function(r) {
      if (!r.ok) { root.sendError = r.error || "not sent"; if (composer.text === "") composer.text = keep }
    })
  }
  function focusComposer() { composer.forceActiveFocus() }
}
