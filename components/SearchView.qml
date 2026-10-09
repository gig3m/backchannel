import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui as Ui
import "Format.js" as Format

// Message search across the workspace, newest first, with Slack's own
// query syntax (from:@name, in:#channel, before:2026-01-01 and so on).
// Picking a result opens its conversation, and its thread for a reply.
Item {
  id: root
  property var service: null
  property string query: ""

  signal resultPicked(string convId, string threadTs)
  signal closeRequested()

  property var results: []
  property int page: 0
  property int pages: 0
  property int total: 0
  property bool loading: false
  property string error: ""

  function run(q) {
    query = String(q || "").trim()
    field.text = query
    results = []
    page = 0; pages = 0; total = 0
    error = ""
    if (query !== "") more()
  }
  function more() {
    if (!service || loading || (pages > 0 && page >= pages)) return
    loading = true
    var q = query, want = page + 1
    service.search(q, want, function(r) {
      if (q !== root.query) return
      root.loading = false
      if (!r.ok) { root.error = r.error || "search failed"; return }
      root.results = root.results.concat(r.result.results || [])
      root.page = r.result.page || want
      root.pages = r.result.pages || 0
      root.total = r.result.total || 0
    })
  }
  function focusField() { field.forceActiveFocus(); field.selectAll() }

  Rectangle {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: field.implicitHeight + Style.space(16)
    color: "transparent"
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Util.alpha(Color.foreground, 0.1) }
    Text {
      id: closeBtn
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: "󰅖"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      MouseArea { anchors.fill: parent; anchors.margins: -Style.space(4); cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
    }
    Ui.TextField {
      id: field
      anchors.left: closeBtn.right
      anchors.right: count.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      placeholderText: "Search messages (from:@name in:#channel)"
      Keys.onReturnPressed: root.run(text)
      Keys.onEscapePressed: root.closeRequested()
    }
    Text {
      id: count
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: root.page > 0 ? root.total + (root.total === 1 ? " result" : " results") : ""
      color: Util.alpha(Color.foreground, 0.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  ListView {
    id: list
    anchors.top: header.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    model: root.results
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    onAtYEndChanged: if (atYEnd && contentHeight > height) root.more()

    delegate: Rectangle {
      id: hit
      required property var modelData
      readonly property var m: modelData.message
      width: ListView.view.width
      height: col.implicitHeight + Style.space(14)
      color: mouse.containsMouse ? Util.alpha(Color.foreground, 0.05) : "transparent"
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Util.alpha(Color.foreground, 0.06) }

      Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(14)
        spacing: Style.space(3)
        Text {
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: (hit.modelData.kind === "channel" ? "#" : hit.modelData.kind === "private" ? "🔒 " : "") + hit.modelData.conv_name
            + (hit.modelData.thread_ts ? " · in a thread" : "")
          color: Util.alpha(Color.foreground, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Row {
          spacing: Style.space(8)
          Text { text: hit.m.user_name || ""; textFormat: Text.PlainText; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Format.dayText(hit.m.ts) + " " + Format.timeText(hit.m.ts)
            color: Util.alpha(Color.foreground, 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          maximumLineCount: 6
          elide: Text.ElideRight
          textFormat: Text.RichText
          text: Format.styleHtml(hit.m.html || "", Color.accent, Util.alpha(Color.foreground, 0.6), Util.alpha(Color.foreground, 0.08))
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.resultPicked(hit.modelData.conv, hit.modelData.thread_ts || "")
      }
    }

    footer: Item {
      width: ListView.view.width
      height: root.loading && root.results.length > 0 ? Style.space(32) : 0
      Text {
        anchors.centerIn: parent
        visible: parent.height > 0
        text: "Loading more…"
        color: Util.alpha(Color.foreground, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  Text {
    anchors.centerIn: list
    visible: root.results.length === 0
    width: list.width - Style.space(40)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: root.loading ? "Searching…" : root.error !== "" ? root.error : root.query === "" ? "Type a search and press Enter." : "No messages match."
    color: root.error !== "" ? Color.urgent : Util.alpha(Color.foreground, 0.5)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}
