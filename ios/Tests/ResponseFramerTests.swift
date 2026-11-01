import Foundation
@main struct ResponseFramerTests {
    static func main() {
        var framer = ResponseFramer()
        precondition(framer.append(Data("L".utf8)).isEmpty)
        precondition(framer.append(Data("OCK OK\r\nUNLOCK".utf8)) == ["LOCK OK"])
        precondition(framer.append(Data(" OK\r\nTRUNK OK\r\n".utf8)) == ["UNLOCK OK", "TRUNK OK"])
        precondition(framer.append(Data(repeating: 65, count: 4097)).isEmpty)
        precondition(framer.append(Data("LOCK OK\n".utf8)) == ["LOCK OK"])
        print("Response framing checks passed")
    }
}
