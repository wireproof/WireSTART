@main struct Tests {
 static func main() {
  precondition(WidgetReply.status(for: "lock ok\r\n", command: "lock") == "Locked")
  precondition(WidgetReply.status(for: "UNLOCK OK", command: "unlock") == "Unlocked")
  precondition(WidgetReply.status(for: "ERR", command: "start") == "Valet")
  precondition(WidgetReply.status(for: "START OK", command: "start") == "Remote Start")
  precondition(WidgetReply.status(for: "STOP OK", command: "start") == "Stopped")
  precondition(WidgetReply.status(for: "TRUNK OK", command: "trunk") == "Trunk Opened")
  precondition(WidgetReply.status(for: "PANIC OK", command: "panic") == "Panic")
  precondition(WidgetReply.status(for: "TRUNK FAILED", command: "trunk") == "Trunk error")
  precondition(WidgetReply.status(for: "START ERROR", command: "start") == "Start error")
  precondition(WidgetReply.status(for: "START OK", command: "trunk") == nil)
  precondition(WidgetReply.status(for: "START", command: "start") == nil)
  print("Widget reply checks passed")
 }
}
