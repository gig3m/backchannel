import QtQuick
import qs.Commons
import "Format.js" as Format

// One message. Consecutive messages from the same person within five
// minutes fold under a single name and avatar, the way Slack shows them.
Item {
  id: row
  property var service: null
  property string convId: ""
  property var msg: ({})
  property var older: null        // the message drawn above this one
  property bool inThread: false
  property bool compact: false

  signal openThread(string ts)
  signal contextRequested(var source, real x, real y)
  signal imageActivated(var file)

  readonly property color fg: Color.foreground
  readonly property color muted: Util.alpha(Color.foreground, 0.6)
  readonly property color accent: Color.accent
  readonly property bool system: !!msg.subtype && msg.subtype !== "bot_message" && msg.subtype !== "thread_broadcast" && msg.subtype !== "file_share" && msg.subtype !== "me_message"
  readonly property bool newDay: !older || !Format.sameDay(older.ts, msg.ts)
  readonly property bool grouped: !newDay && older && !older.subtype && !system
    && older.user_name === msg.user_name && (parseFloat(msg.ts) - parseFloat(older.ts)) < 300
  readonly property bool avatars: service ? service.showAvatars && !compact : !compact
  readonly property int avatarSize: Style.space(32)
  readonly property int gutter: avatars ? avatarSize + Style.space(10) : 0

  implicitHeight: column.implicitHeight + (grouped ? Style.space(2) : Style.space(8))

  HoverHandler { id: hover }

  Rectangle {
    anchors.fill: parent
    color: hover.hovered ? Util.alpha(Color.foreground, 0.04) : "transparent"
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(12)
    spacing: Style.space(2)

    // Day divider
    Item {
      visible: row.newDay
      width: parent.width
      height: visible ? Style.space(28) : 0
      Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: Util.alpha(Color.foreground, 0.12) }
      Rectangle {
        anchors.centerIn: parent
        width: dayLabel.implicitWidth + Style.space(16); height: dayLabel.implicitHeight + Style.space(4)
        color: Color.background
        Text { id: dayLabel; anchors.centerIn: parent; text: Format.dayText(row.msg.ts); color: row.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
      }
    }

    Item {
      width: parent.width
      height: Math.max(body.implicitHeight, row.grouped || !row.avatars ? 0 : row.avatarSize)
      implicitHeight: height

      Image {
        visible: row.avatars && !row.grouped && !row.system
        width: row.avatarSize; height: row.avatarSize
        source: visible && row.msg.avatar ? row.msg.avatar : ""
        sourceSize.width: row.avatarSize * 2
        sourceSize.height: row.avatarSize * 2
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        Rectangle { anchors.fill: parent; visible: parent.status !== Image.Ready; color: Util.alpha(Color.foreground, 0.1) }
      }
      // Time in the gutter on folded messages, on hover
      Text {
        visible: row.grouped && hover.hovered && row.avatars
        width: row.gutter - Style.space(6)
        horizontalAlignment: Text.AlignRight
        y: Style.space(2)
        text: Format.timeText(row.msg.ts)
        color: row.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Column {
        id: body
        x: row.gutter
        width: parent.width - row.gutter
        spacing: Style.space(3)

        Row {
          visible: !row.grouped && !row.system
          spacing: Style.space(8)
          Text {
            text: row.msg.user_name || ""
            textFormat: Text.PlainText
            color: row.msg.own ? row.accent : row.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            visible: row.msg.bot === true
            text: "APP"
            color: row.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: Format.timeText(row.msg.ts)
            color: row.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        TextEdit {
          id: text
          visible: (row.msg.html || "") !== ""
          width: parent.width
          readOnly: true
          selectByMouse: true
          textFormat: TextEdit.RichText
          wrapMode: TextEdit.Wrap
          color: row.system ? row.muted : row.fg
          selectionColor: Util.alpha(Color.accent, 0.35)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.italic: row.system || row.msg.subtype === "me_message"
          text: Format.styleHtml(row.msg.html, row.accent, row.muted, Util.alpha(Color.foreground, 0.08))
            + (row.msg.edited ? ' <span style="color:' + row.muted + '; font-size:small">(edited)</span>' : "")
          onLinkActivated: function(link) { if (row.service) row.service.openUrl(link) }
          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: text.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
          }
        }

        // Files: images inline once the daemon has fetched them, others as chips.
        Repeater {
          model: row.msg.files || []
          delegate: Loader {
            required property var modelData
            sourceComponent: modelData.image ? imageFile : otherFile
            property var file: modelData
          }
        }

        // Reactions
        Flow {
          visible: (row.msg.reactions || []).length > 0
          width: parent.width
          spacing: Style.space(4)
          Repeater {
            model: row.msg.reactions || []
            delegate: Rectangle {
              required property var modelData
              width: chip.implicitWidth + Style.space(12)
              height: chip.implicitHeight + Style.space(4)
              color: modelData.me ? Util.alpha(Color.accent, 0.18) : Util.alpha(Color.foreground, 0.06)
              border.width: 1
              border.color: modelData.me ? Color.accent : "transparent"
              Text {
                id: chip
                anchors.centerIn: parent
                text: (modelData.emoji || ":" + modelData.name + ":") + " " + modelData.count
                color: row.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (row.service) row.service.react(row.convId, row.msg.ts, modelData.name, !modelData.me, null)
              }
            }
          }
        }

        // Thread footer
        Text {
          visible: !row.inThread && (row.msg.reply_count || 0) > 0
          text: row.msg.reply_count + (row.msg.reply_count === 1 ? " reply" : " replies")
            + (row.msg.latest_reply ? "  ·  last " + Format.dayText(row.msg.latest_reply).toLowerCase().replace("today", Format.timeText(row.msg.latest_reply)) : "")
          color: row.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: row.openThread(row.msg.ts) }
        }
      }
    }
  }

  // Hover actions: quick reactions and reply in thread.
  Rectangle {
    visible: hover.hovered && !row.system
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.top: parent.top
    anchors.topMargin: row.newDay ? Style.space(28) : -Style.space(4)
    width: actions.implicitWidth + Style.space(8)
    height: actions.implicitHeight + Style.space(4)
    color: Color.background
    border.width: 1
    border.color: Util.alpha(Color.foreground, 0.15)
    z: 2
    Row {
      id: actions
      anchors.centerIn: parent
      spacing: Style.space(2)
      Repeater {
        model: [{ n: "+1", e: "👍" }, { n: "white_check_mark", e: "✅" }, { n: "eyes", e: "👀" }, { n: "joy", e: "😂" }]
        delegate: Text {
          required property var modelData
          text: modelData.e
          font.pixelSize: Style.font.title
          padding: Style.space(3)
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (row.service) row.service.react(row.convId, row.msg.ts, modelData.n, true, null) }
        }
      }
      Text {
        visible: !row.inThread
        text: "󰍪"
        color: row.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        padding: Style.space(3)
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: row.openThread(row.msg.ts) }
      }
    }
  }

  Component {
    id: imageFile
    // Up to 360×300, the image's own proportions, never scaled up.
    Item {
      id: box
      property var f: parent ? parent.file : null
      property string path: ""
      readonly property bool ready: img.status === Image.Ready && img.sourceSize.width > 0
      readonly property real scale: ready ? Math.min(1, Style.space(360) / img.sourceSize.width, Style.space(300) / img.sourceSize.height) : 1
      width: ready ? Math.round(img.sourceSize.width * scale) : Style.space(240)
      height: ready ? Math.round(img.sourceSize.height * scale) : Style.space(36)
      implicitWidth: width
      implicitHeight: height
      // A Loader parents its item after creating it, so `f` can still be
      // null at onCompleted; fetch whenever it (or the service) arrives.
      property bool requested: false
      function load() {
        if (box.requested || !box.f || !row.service) return
        box.requested = true
        var id = box.f.id
        row.service.filePath(id, function(p) { if (box.f && box.f.id === id) box.path = p })
      }
      onFChanged: { box.requested = false; box.path = ""; load() }
      Component.onCompleted: load()
      Image {
        id: img
        anchors.fill: parent
        source: box.path ? "file://" + box.path : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
      }
      Rectangle {
        anchors.fill: parent
        visible: !box.ready
        color: Util.alpha(Color.foreground, 0.06)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          x: Style.space(8)
          text: "󰋩 " + (box.f ? box.f.name : "")
          color: row.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (box.f) row.imageActivated(box.f) }
    }
  }

  Component {
    id: otherFile
    Rectangle {
      property var f: parent ? parent.file : null
      width: fileLabel.implicitWidth + Style.space(16)
      height: fileLabel.implicitHeight + Style.space(8)
      implicitWidth: width
      implicitHeight: height
      color: Util.alpha(Color.foreground, 0.06)
      Text {
        id: fileLabel
        anchors.centerIn: parent
        text: "󰈔 " + (parent.f ? parent.f.name + "  ·  " + Format.sizeText(parent.f.size) : "") + "   󰇚"
        color: row.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      // Click saves to Downloads; the notification opens it.
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (parent.f && row.service) row.service.saveFile(parent.f.id, parent.f.name) }
    }
  }

  // Right-click anywhere on the message, images included. Left clicks and
  // text selection pass through.
  MouseArea {
    id: ctxArea
    anchors.fill: parent
    z: 3
    acceptedButtons: Qt.RightButton
    onClicked: function(ev) { row.contextRequested(ctxArea, ev.x, ev.y) }
  }
}
