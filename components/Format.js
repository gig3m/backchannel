.pragma library

// Slack timestamps are "seconds.micros" strings.
function tsDate(ts) {
  var s = parseFloat(String(ts || "0"))
  return new Date(s * 1000)
}

function timeText(ts) {
  if (!ts) return ""
  var d = tsDate(ts)
  var h = d.getHours(), m = d.getMinutes()
  return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
}

function dayText(ts) {
  if (!ts) return ""
  var d = tsDate(ts)
  var today = new Date()
  var start = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()
  var t = d.getTime()
  if (t >= start) return "Today"
  if (t >= start - 86400000) return "Yesterday"
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  if (t >= start - 6 * 86400000) return days[d.getDay()]
  return months[d.getMonth()] + " " + d.getDate() + (d.getFullYear() !== today.getFullYear() ? ", " + d.getFullYear() : "")
}

function sameDay(a, b) {
  if (!a || !b) return false
  var x = tsDate(a), y = tsDate(b)
  return x.getFullYear() === y.getFullYear() && x.getMonth() === y.getMonth() && x.getDate() === y.getDate()
}

// The daemon renders Slack markup to a small HTML subset with class names;
// Qt's RichText ignores classes, so colors are inlined here, where the
// theme is known.
function styleHtml(html, accent, muted, codeBg) {
  return String(html || "")
    .replace(/<span class="mention">/g, '<span style="color:' + accent + '; font-weight:600">')
    .replace(/<a href=/g, '<a style="color:' + accent + '" href=')
    .replace(/<code>/g, '<code style="background-color:' + codeBg + '">')
    .replace(/<pre>/g, '<pre style="background-color:' + codeBg + '">')
    .replace(/<blockquote>/g, '<blockquote style="color:' + muted + '">')
}

function sizeText(n) {
  n = Number(n) || 0
  if (n < 1024) return n + " B"
  if (n < 1048576) return Math.round(n / 1024) + " KB"
  return (n / 1048576).toFixed(1) + " MB"
}

// Text from other people, as a notification argument: never empty, never
// starting with "-" (the notification script would read it as an option).
function notifyText(s) {
  var t = String(s == null ? "" : s).replace(/[\u0000-\u001f]/g, " ").trim()
  if (t === "") return "…"
  return t.charAt(0) === "-" ? "‒" + t.substring(1) : t
}

function safeUrl(u) {
  var s = String(u || "")
  return /^(https?:\/\/|mailto:)/i.test(s) ? s : ""
}
