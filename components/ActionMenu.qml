import QtQuick
import QtQuick.Controls
import qs.Commons

// A right-click menu for the window and the popup, drawn like the bar
// menu. Items: { id, icon, label, enabled, danger, sep, confirm }. An item
// with `confirm` (a label) asks for a second click before it fires. An
// item with `emojis: [{ n, e }]` is a row of quick reactions; picking one
// triggers "react:<n>".
Popup {
  id: root
  property var items: []
  property var context: null      // whatever the opener wants back
  signal triggered(string id, var context)

  property int current: -1
  property string confirming: ""

  readonly property int menuWidth: Style.space(250)
  padding: Style.space(5)
  implicitWidth: menuWidth + leftPadding + rightPadding
  implicitHeight: column.implicitHeight + topPadding + bottomPadding
  modal: false
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  // Open at a point in `item`'s coordinates, kept inside the parent.
  function show(item, x, y, items, context) {
    root.items = items || []
    root.context = context === undefined ? null : context
    root.confirming = ""
    root.current = -1
    var p = item.mapToItem(root.parent, x, y)
    root.x = p.x
    root.y = p.y
    root.open()
    Qt.callLater(root.clamp)
  }

  // Keep the whole menu inside the window once its size is known.
  function clamp() {
    if (!root.parent) return
    root.x = Math.max(0, Math.min(root.x, root.parent.width - root.width))
    root.y = Math.max(0, Math.min(root.y, root.parent.height - root.height))
  }

  function move(step) {
    var n = root.items.length, i = root.current
    for (var k = 0; k < n; k++) {
      i = (i + step + n) % n
      var it = root.items[i]
      if (!it.sep && !it.emojis && it.enabled !== false) { root.current = i; return }
    }
  }

  function activate(it) {
    if (!it || it.sep || it.enabled === false) return
    if (it.confirm && root.confirming !== it.id) { root.confirming = it.id; return }
    var ctx = root.context
    root.close()
    root.triggered(it.id, ctx)
  }

  background: Rectangle {
    color: Color.popups.background
    border.width: 1
    border.color: Color.popups.border
  }

  contentItem: Column {
    id: column
    width: root.menuWidth
    focus: true
    Keys.onUpPressed: root.move(-1)
    Keys.onDownPressed: root.move(1)
    Keys.onReturnPressed: if (root.current >= 0) root.activate(root.items[root.current])
    Keys.onEnterPressed: if (root.current >= 0) root.activate(root.items[root.current])

    Repeater {
      model: root.items
      delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property bool enabledItem: modelData.enabled !== false
        readonly property bool asking: root.confirming === modelData.id
        width: root.menuWidth
        height: modelData.sep ? Style.space(9) : modelData.emojis ? Style.spacing.popupRowHeight + Style.space(6) : Style.spacing.popupRowHeight

        Row {
          visible: !!row.modelData.emojis
          anchors.verticalCenter: parent.verticalCenter
          x: Style.space(4)
          spacing: Style.space(2)
          Repeater {
            model: row.modelData.emojis || []
            delegate: Rectangle {
              required property var modelData
              width: Style.space(34); height: Style.space(30)
              color: hov.containsMouse ? Util.alpha(Color.foreground, 0.1) : "transparent"
              Text { anchors.centerIn: parent; text: modelData.e; font.pixelSize: Style.font.heading }
              MouseArea {
                id: hov
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { var ctx = root.context; root.close(); root.triggered("react:" + modelData.n, ctx) }
              }
            }
          }
        }

        Rectangle {
          visible: row.modelData.sep === true
          anchors.verticalCenter: parent.verticalCenter
          x: Style.space(6)
          width: parent.width - Style.space(12)
          height: 1
          color: Util.alpha(Color.foreground, 0.12)
        }

        Rectangle {
          visible: !row.modelData.sep && !row.modelData.emojis
          anchors.fill: parent
          color: row.index === root.current && row.enabledItem ? Util.alpha(Color.foreground, 0.08) : "transparent"
          Row {
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(8)
            spacing: Style.space(10)
            Text {
              width: Style.space(16)
              text: row.modelData.icon || ""
              color: row.modelData.danger || row.asking ? Color.urgent : Color.foreground
              opacity: row.enabledItem ? 1 : 0.4
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Text {
              text: row.asking ? row.modelData.confirm : (row.modelData.label || "")
              textFormat: Text.PlainText
              color: row.modelData.danger || row.asking ? Color.urgent : Color.foreground
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
