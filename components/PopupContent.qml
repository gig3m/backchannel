import QtQuick
import qs.Commons
import qs.Ui as Ui

// The bar popup: what needs attention, and a compact conversation with a
// composer when one is picked. The full window is a click away.
Item {
  id: root
  property var service: null
  property var bar: null
  property bool opened: false
  property bool menuMode: false
  signal closeRequested()
  signal showConversations()

  readonly property bool hasTextFocus: (list.visible && list.hasTextFocus) || (conv.visible && conv.hasTextFocus) || (setup.visible && setup.hasTextFocus)
  readonly property bool loggedIn: service ? service.loggedIn : false

  implicitHeight: menuMode ? menu.implicitHeight : loggedIn ? Style.space(560) : setup.implicitHeight

  function openConversation(id) { conv.open(id, ""); Qt.callLater(conv.focusComposer) }
  // Escape: back out of a conversation first, then close.
  function handleClose() {
    if (root.menuMode) return false
    if (conv.visible) { conv.convId = ""; return true }
    return false
  }
  onOpenedChanged: {
    if (!opened) { list.closeMenus(); conv.closeMenus() }
    if (opened && loggedIn && !conv.visible && !menuMode) Qt.callLater(list.focusSearch)
  }
  onMenuModeChanged: {
    if (menuMode) { menu.reset(); Qt.callLater(function() { menu.forceActiveFocus() }) }
    else if (opened && loggedIn && !conv.visible) Qt.callLater(list.focusSearch)
  }

  BarMenu {
    id: menu
    anchors.fill: parent
    visible: root.menuMode
    service: root.service
    onCloseRequested: root.closeRequested()
    onShowConversations: root.showConversations()
  }

  SetupView {
    id: setup
    anchors.fill: parent
    visible: !root.loggedIn && !root.menuMode
    service: root.service
  }

  Item {
    anchors.fill: parent
    visible: root.loggedIn && !root.menuMode

    Rectangle {
      id: header
      visible: !conv.visible
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: visible ? headerRow.implicitHeight + Style.space(14) : 0
      color: "transparent"
      Row {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(8)
        Text {
          width: parent.width - openBtn.width
          anchors.verticalCenter: parent.verticalCenter
          text: root.service ? root.service.stateText : ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Ui.Button {
          id: openBtn
          text: "Open  󰏌"
          onClicked: { root.service.openWindow(); root.closeRequested() }
        }
      }
    }

    ConversationList {
      id: list
      visible: !conv.visible
      anchors.top: header.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      service: root.service
      compact: true
      onPicked: function(id) { root.openConversation(id) }
    }

    ConversationView {
      id: conv
      visible: convId !== ""
      anchors.fill: parent
      service: root.service
      viewId: "popup"
      compact: true
      active: root.opened && visible
      onCloseRequested: { conv.convId = ""; Qt.callLater(list.focusSearch) }
      onOpenThread: function(ts) { root.service.openWindow({ conv: conv.convId, thread: ts }); root.closeRequested() }
      // Too small for a preview here: hand the image to the viewer.
      onPreviewImage: function(file) { root.service.openFile(file.id); root.closeRequested() }
    }
  }
}
