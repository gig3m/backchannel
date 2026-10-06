import QtQuick
import qs.Commons
import qs.Ui as Ui
import "Format.js" as Format

// A full-size image over the window: the picture fitted to the space, its
// name, and Save / Copy / Open / Open in Slack. Esc, the close button or a
// click on the backdrop closes it. GIFs play.
Rectangle {
  id: root
  property var service: null
  property var file: null          // { id, name, mimetype, size, link }
  property string convId: ""
  property string ts: ""
  property string threadTs: ""
  property string path: ""
  readonly property bool shown: visible

  visible: false
  color: Util.alpha(Color.background, 0.94)
  focus: visible
  z: 50

  function show(file, convId, ts, threadTs) {
    root.file = file
    root.convId = convId || ""
    root.ts = ts || ""
    root.threadTs = threadTs || ""
    root.path = ""
    root.visible = true
    root.forceActiveFocus()
    if (service && file) service.filePath(file.id, function(p) { if (root.file === file) root.path = p })
  }
  function hide() { root.visible = false; root.file = null; root.path = "" }

  Keys.onEscapePressed: root.hide()

  // Backdrop: clicking outside the picture closes.
  MouseArea { anchors.fill: parent; onClicked: root.hide() }

  Rectangle {
    id: bar
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: barRow.implicitHeight + Style.space(16)
    color: Util.alpha(Color.background, 0.9)
    MouseArea { anchors.fill: parent }   // clicks on the bar do not close

    Row {
      id: barRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(14)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(6)

      Column {
        width: parent.width - buttons.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        Text {
          width: parent.width
          text: root.file ? root.file.name : ""
          textFormat: Text.PlainText
          elide: Text.ElideMiddle
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          text: root.file ? Format.sizeText(root.file.size) + (img.status === Image.Ready ? "  ·  " + img.sourceSize.width + "×" + img.sourceSize.height : "") : ""
          color: Util.alpha(Color.foreground, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: buttons
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        Ui.Button { text: "󰇚  Save"; enabled: root.path !== ""; onClicked: root.service.saveFile(root.file.id, root.file.name) }
        Ui.Button { text: "󰆏  Copy"; enabled: root.path !== ""; onClicked: root.service.copyImage(root.file.id) }
        Ui.Button { text: "󰏌  Open"; tooltipText: "Open in your image viewer"; enabled: root.path !== ""; onClicked: { root.service.openFile(root.file.id); root.hide() } }
        Ui.Button {
          text: "󰒱  Slack"
          tooltipText: "Open the message in Slack"
          onClicked: root.service.openUrl(root.service.permalink(root.convId, root.ts, root.threadTs))
        }
        Ui.Button { text: "󰅖"; tooltipText: "Close (Esc)"; onClicked: root.hide() }
      }
    }
  }

  // The picture, fitted inside the space below the bar and never scaled up.
  Item {
    id: stage
    anchors.top: bar.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(20)

    AnimatedImage {
      id: img
      anchors.centerIn: parent
      source: root.path ? "file://" + root.path : ""
      width: status === Image.Ready ? Math.min(stage.width, sourceSize.width) : 0
      height: status === Image.Ready ? Math.min(stage.height, sourceSize.height) : 0
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      playing: root.visible
      smooth: true
      mipmap: true
      // A click on the picture itself does not close.
      MouseArea { anchors.centerIn: parent; width: parent.paintedWidth; height: parent.paintedHeight }
    }

    Text {
      anchors.centerIn: parent
      visible: img.status !== Image.Ready
      text: img.status === Image.Error ? "Could not show this image." : "Loading…"
      color: Util.alpha(Color.foreground, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
}
