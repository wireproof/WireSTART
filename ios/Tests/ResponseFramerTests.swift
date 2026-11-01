import Foundation
@main struct ResponseFramerTests {
    static func main() {
        var framer = ResponseFramer()
        precondition(framer.append(Data("L".utf8)).isEmpty)
        precondition(framer.append(Data("OCK OK\r\nUNLOCK".utf8)) == ["LOCK OK"])
        precondition(framer.append(Data(" OK\r\nTRUNK OK\r\n".utf8)) == ["UNLOCK OK", "TRUNK OK"])
        precondition(framer.append(Data(repeating: 65, count: 4097)).isEmpty)
        precondition(framer.append(Data("LOCK OK\n".utf8)) == ["LOCK OK"])
        var partial = ResponseFramer()
        precondition(partial.append(Data("E".utf8)).isEmpty)
        precondition(partial.append(Data("RR".utf8)).isEmpty)
        precondition(partial.partialText == "ERR")
        precondition(partial.append(Data("\n".utf8)) == ["ERR"])
        precondition(partial.partialText == nil)
        precondition(partial.append(Data("E".utf8)).isEmpty)
        precondition(partial.append(Data("RR".utf8)).isEmpty)
        precondition(partial.takePartialText() == "ERR")
        precondition(partial.partialText == nil)
        precondition(partial.append(Data("RR".utf8)).isEmpty)
        precondition(partial.takePartialText() == "RR")
        print("Response framing checks passed")
    }
}
