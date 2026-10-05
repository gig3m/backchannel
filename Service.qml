import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "components/Format.js" as Format

// Backchannel service: the one connection to backchanneld, the session
// state, the conversation list and desktop notifications. Mounted when the
// shell starts. The bar popup (Panel.qml) and the window (Window.qml) are
// views over this object and never talk to the socket themselves.
//
// The tokens pass through here exactly once, on setup: straight to the
// socket (0600, peer-uid checked), never stored by the plugin.
Item {
  id: root
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "gig3m.backchannel"
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR")
  readonly property string socketPath: runtimeDir + "/backchannel.sock"
  readonly property string daemonUnit: "backchanneld"
  readonly property string glyph: "󰒱"
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string pluginVersion: (manifest && manifest.version) ? String(manifest.version) : ""

  function log(msg) { console.log("[backchannel] " + msg) }

  // ---------- settings (bar layout entry over manifest defaults) ----------

  readonly property var defaults: (manifest && manifest.barWidget && manifest.barWidget.defaults) ? manifest.barWidget.defaults : ({})
  readonly property var layoutEntry: findLayoutEntry(shell ? shell.barConfig : null)
  function findLayoutEntry(cfg) {
    if (!cfg || !cfg.layout) return null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var list = cfg.layout[sections[s]]
      if (!list) continue
      for (var i = 0; i < list.length; i++) if (list[i] && String(list[i].id) === pluginId) return list[i]
    }
    return null
  }
  // Values applied ahead of the shell.json round-trip, so a toggle in the
  // menu shows its new state at once.
  property var overrides: ({})
  onLayoutEntryChanged: {
    var e = layoutEntry, o = root.overrides, keep = {}, changed = false
    for (var k in o) { if (e && e[k] === o[k]) changed = true; else keep[k] = o[k] }
    if (changed) root.overrides = keep
  }
  // Persist through the shell's inline writer (what its own bar gestures
  // use); fall back to `omarchy-bar-set` per key.
  function set(key, value) {
    var o = Object.assign({}, root.overrides); o[key] = value; root.overrides = o
    if (shell && typeof shell.updateEntryInline === "function" && layoutEntry) {
      var merged = {}
      for (var k in layoutEntry) if (k !== "id") merged[k] = layoutEntry[k]
      merged[key] = value
      shell.updateEntryInline(pluginId, merged)
      return
    }
    var argv = ["/usr/bin/omarchy-bar", "set", pluginId, key, typeof value === "string" ? value : JSON.stringify(value)]
    if (typeof value !== "string") argv.push("--json")
    Quickshell.execDetached(argv)
  }
  function setting(key, fallback) {
    if (root.overrides[key] !== undefined) return root.overrides[key]
    var e = layoutEntry
    if (e && e[key] !== undefined && e[key] !== null) return e[key]
    if (defaults && defaults[key] !== undefined) return defaults[key]
    return fallback
  }
  function flag(key, fallback) {
    var v = setting(key, fallback)
    if (v === true || v === false) return v
    var s = String(v).toLowerCase()
    if (s === "false" || s === "0" || s === "off" || s === "no") return false
    if (s === "true" || s === "1" || s === "on" || s === "yes") return true
    return fallback
  }
  readonly property string clickAction: String(setting("clickAction", "popup")) === "window" ? "window" : "popup"
  readonly property bool notificationsEnabled: flag("notifications", true)
  readonly property bool notifyAllChannels: String(setting("notifyChannels", "mentions")) === "all"
  readonly property bool autostartDaemon: flag("autostartDaemon", true)
  readonly property bool showAvatars: flag("showAvatars", true)
  readonly property bool hideQuietChannels: flag("hideQuietChannels", false)

  // ---------- state ----------

  property bool installed: false        // backchanneld is on PATH
  property bool checked: false          // the PATH check has answered once
  property bool connected: false        // the socket is up
  property bool starting: false
  property var status: ({ logged_in: false, connected: false })
  property var conversations: []
  readonly property bool loggedIn: status.logged_in === true
  readonly property string userId: status.user_id || ""
  readonly property string teamName: status.team || ""

  readonly property int unreadTotal: {
    var n = 0
    for (var i = 0; i < conversations.length; i++) if (conversations[i].unread > 0) n++
    return n
  }
  readonly property int mentionTotal: {
    var n = 0
    for (var i = 0; i < conversations.length; i++) n += Number(conversations[i].mentions) || 0
    return n
  }
  readonly property string stateText: {
    if (!checked) return "Starting…"
    if (!installed) return "backchanneld is not installed"
    if (!connected) return starting ? "Starting the daemon…" : "Daemon not running"
    if (!loggedIn) return status.error ? status.error : "Not signed in"
    if (!status.connected) return teamName + " · reconnecting…"
    if (status.loading) return teamName + " · catching up…"
    return teamName
  }

  // Views tell the service what they show, so a message there neither
  // notifies nor counts as unread. viewId → conversation id.
  property var viewing: ({})
  function setViewing(viewId, convId) {
    var v = Object.assign({}, root.viewing)
    if (convId) v[viewId] = convId; else delete v[viewId]
    root.viewing = v
  }
  function isViewed(convId) {
    for (var k in root.viewing) if (root.viewing[k] === convId) return true
    return false
  }

  signal messageReceived(var ev)
  signal messageChanged(var ev)
  signal messageDeleted(var ev)
  signal reactionChanged(var ev)

  // ---------- daemon ----------

  Process {
    id: whichProc
    command: ["sh", "-c", "command -v backchanneld"]
    onExited: function(code) {
      root.installed = code === 0
      root.checked = true
      if (root.installed) root.ensureDaemon()
    }
  }
  function checkInstalled() { whichProc.running = true }

  Process {
    id: startProc
    command: ["systemctl", "--user", "start", root.daemonUnit + ".service"]
    onExited: function(code) {
      if (code !== 0) { root.starting = false; root.log("systemctl start exited " + code) }
      else connectTimer.restart()
    }
  }
  function ensureDaemon() {
    if (!root.installed) { root.checkInstalled(); return }
    if (root.connected) return
    root.connectSocket()
    if (root.autostartDaemon && !root.starting) { root.starting = true; startProc.running = true }
  }
  Timer { id: connectTimer; interval: 400; onTriggered: root.connectSocket() }

  // ---------- socket ----------

  // A Socket that was dropped by the server does not reconnect however
  // `connected` is toggled, so every attempt gets a fresh object.
  property var sock: null
  property int nextId: 1
  property var pending: ({})

  function connectSocket() {
    if (!root.installed || root.connected) return
    if (root.sock) { root.sock.destroy(); root.sock = null }
    root.sock = sockComponent.createObject(root)
    root.sock.connected = true
  }

  Component {
    id: sockComponent
    Socket {
      path: root.socketPath
      parser: SplitParser { onRead: function(line) { root.onLine(line) } }
      onConnectionStateChanged: {
        if (this !== root.sock) return
        root.connected = connected
        if (connected) {
          root.starting = false
          root.request("status", {}, function(r) { if (r.ok) root.applyStatus(r.result) })
        } else {
          root.failPending("daemon disconnected")
          root.conversations = []
          root.status = ({ logged_in: false, connected: false })
          var dead = root.sock
          root.sock = null
          dead.destroy()
        }
      }
    }
  }

  // The socket does not reconnect by itself; poll while the daemon is away.
  Timer {
    interval: 5000
    repeat: true
    running: root.installed && !root.connected
    onTriggered: root.connectSocket()
  }

  function failPending(reason) {
    var p = root.pending
    root.pending = ({})
    for (var id in p) { try { p[id].cb({ ok: false, error: reason }) } catch (e) { root.log("callback: " + e) } }
  }
  // A request with no reply is failed back to its caller, so nothing waits forever.
  Timer {
    interval: 10 * 1000
    repeat: true
    running: root.connected
    onTriggered: {
      var now = Date.now(), p = root.pending, late = []
      for (var id in p) if (now - p[id].at > 90 * 1000) late.push(id)
      if (late.length === 0) return
      var keep = Object.assign({}, p)
      for (var i = 0; i < late.length; i++) delete keep[late[i]]
      root.pending = keep
      for (var j = 0; j < late.length; j++) { try { p[late[j]].cb({ ok: false, error: "no reply from the daemon" }) } catch (e) { root.log("callback: " + e) } }
    }
  }

  function request(cmd, fields, cb) {
    if (!root.sock || !root.sock.connected) { if (cb) cb({ ok: false, error: "daemon not connected" }); return }
    var id = root.nextId++
    var obj = Object.assign({}, fields || {})
    obj.id = id
    obj.cmd = cmd
    if (cb) { var p = root.pending; p[id] = { cb: cb, at: Date.now() }; root.pending = p }
    root.sock.write(JSON.stringify(obj) + "\n")
    root.sock.flush()
  }

  function onLine(line) {
    var s = String(line).trim()
    if (s === "") return
    var msg
    try { msg = JSON.parse(s) } catch (e) { root.log("bad line from daemon: " + s.slice(0, 200)); return }
    if (msg.event !== undefined) { root.onEvent(msg); return }
    var entry = root.pending[msg.id]
    if (entry) {
      var p = root.pending; delete p[msg.id]; root.pending = p
      entry.cb(msg)
    }
  }

  function applyStatus(s) {
    var was = root.loggedIn
    root.status = s
    if (root.loggedIn && !was) root.refreshConversations()
    if (!root.loggedIn) root.conversations = []
  }

  function onEvent(ev) {
    switch (ev.event) {
    case "state":
      root.applyStatus(ev)
      break
    case "conversations":
      root.conversations = ev.conversations || []
      break
    case "conversation":
      root.upsertConversation(ev)
      break
    case "conversations_changed":
      root.refreshConversations()
      break
    case "message":
      root.messageReceived(ev)
      if (root.isViewed(ev.conv) && !ev.in_thread) root.markRead(ev.conv, ev.message.ts)
      else if (ev.notify || (root.notifyAllChannels && !ev.message.own && !ev.in_thread)) root.notify(ev)
      break
    case "message_changed":
      root.messageChanged(ev)
      break
    case "message_deleted":
      root.messageDeleted(ev)
      break
    case "reaction":
      root.reactionChanged(ev)
      break
    }
  }

  // ---------- conversations ----------

  function refreshConversations() {
    root.request("conversations", {}, function(r) { if (r.ok) root.conversations = r.result || [] })
  }
  function upsertConversation(c) {
    // Strip the event field the daemon adds.
    delete c.event
    var list = root.conversations.slice()
    var found = false
    for (var i = 0; i < list.length; i++) if (list[i].id === c.id) { list[i] = c; found = true; break }
    if (!found) list.push(c)
    root.conversations = list
  }
  function conversationById(id) {
    for (var i = 0; i < root.conversations.length; i++) if (root.conversations[i].id === id) return root.conversations[i]
    return null
  }
  function conversationName(c) {
    if (!c) return ""
    if (c.kind === "channel") return "#" + c.name
    if (c.kind === "private") return "🔒 " + c.name
    return c.name
  }

  // Mark-read calls are debounced per conversation: a burst of messages in
  // the open view sends one mark.
  property var markQueue: ({})
  function markRead(convId, ts) {
    if (!convId || !ts) return
    var q = Object.assign({}, root.markQueue)
    if (!q[convId] || ts > q[convId]) q[convId] = ts
    root.markQueue = q
    markTimer.restart()
  }
  Timer {
    id: markTimer
    interval: 800
    onTriggered: {
      var q = root.markQueue
      root.markQueue = ({})
      for (var id in q) {
        var c = root.conversationById(id)
        if (c && c.last_read && c.last_read >= q[id] && !c.unread) continue
        root.request("mark", { conv: id, ts: q[id] }, null)
      }
    }
  }

  function markAllRead() {
    for (var i = 0; i < root.conversations.length; i++) {
      var c = root.conversations[i]
      if (c.unread > 0 && c.latest) root.request("mark", { conv: c.id, ts: c.latest }, null)
    }
  }
  function restartDaemon() { Quickshell.execDetached(["systemctl", "--user", "restart", root.daemonUnit + ".service"]) }

  function history(convId, before, cb) { root.request("history", { conv: convId, before: before || "", limit: 50 }, cb) }
  function replies(convId, ts, cb) { root.request("replies", { conv: convId, ts: ts }, cb) }
  function send(convId, text, threadTs, cb) { root.request("send", { conv: convId, text: text, thread_ts: threadTs || "" }, cb) }
  function react(convId, ts, name, on, cb) { root.request("react", { conv: convId, ts: ts, name: name, on: on === true }, cb) }
  function upload(convId, path, text, threadTs, cb) { root.request("upload", { conv: convId, path: String(path), text: text || "", thread_ts: threadTs || "" }, cb) }

  // Image previews: the daemon downloads with the token and hands back a
  // cached path. Remember answers so a scrolled-back row does not ask again.
  property var filePaths: ({})
  function filePath(id, cb) {
    if (root.filePaths[id]) { cb(root.filePaths[id]); return }
    root.request("file", { file: id }, function(r) {
      if (!r.ok) { cb(""); return }
      var m = Object.assign({}, root.filePaths); m[id] = r.result.path; root.filePaths = m
      cb(r.result.path)
    })
  }

  // ---------- setup ----------

  FileView {
    id: appManifest
    path: root.pluginDir + "/slack-app-manifest.json"
    blockLoading: true
  }
  // Opens Slack's "create an app" page with the manifest filled in.
  function createAppUrl() {
    var json = ""
    try { var m = JSON.parse(appManifest.text()); delete m._metadata; json = JSON.stringify(m) } catch (e) { json = "" }
    return "https://api.slack.com/apps?new_app=1" + (json ? "&manifest_json=" + encodeURIComponent(json) : "")
  }
  function openUrl(u) {
    var s = Format.safeUrl(u)
    if (s !== "") Quickshell.execDetached(["/usr/share/omarchy/bin/omarchy-launch-browser", s])
  }
  function openCreateApp() { root.openUrl(root.createAppUrl()) }

  function setup(userToken, appToken, cb) {
    root.request("setup", { user_token: String(userToken).trim(), app_token: String(appToken).trim() }, function(r) {
      if (r.ok) root.applyStatus(r.result)
      cb(r)
    })
  }
  function logout(cb) {
    root.request("logout", {}, function(r) { root.conversations = []; if (cb) cb(r) })
  }

  // ---------- notifications ----------

  // Omarchy's notifier: themed, and clicking it opens the conversation.
  function notify(ev) {
    if (!root.notificationsEnabled) return
    var c = root.conversationById(ev.conv)
    var m = ev.message || {}
    var direct = ev.direct === true
    var who = m.user_name || "Someone"
    var title = Format.notifyText(direct ? who : who + " · " + root.conversationName(c))
    var body = m.text ? Format.notifyText(String(m.text).slice(0, 300))
      : (m.files && m.files.length ? "󰈔 " + Format.notifyText(m.files[0].name) : "…")
    Quickshell.execDetached(["/usr/share/omarchy/bin/omarchy-notification-send", "--app-name", "Backchannel", "-g", root.glyph,
      "-u", m.mention ? "critical" : "normal", title, body,
      "--exec", "omarchy-shell", "shell", "summon", root.pluginId, JSON.stringify({ conv: ev.conv, thread: ev.in_thread ? m.thread_ts : "" })])
  }

  // ---------- window ----------

  function openWindow(payload) {
    if (root.shell && typeof root.shell.summon === "function") root.shell.summon(root.pluginId, payload ? JSON.stringify(payload) : "{}")
  }

  Component.onCompleted: checkInstalled()
}
