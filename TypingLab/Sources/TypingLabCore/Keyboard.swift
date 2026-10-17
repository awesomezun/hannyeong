import Foundation

public struct KeyStroke: Equatable, Sendable {
    public let character: String
    public let base: String
    public let code: UInt16
    public let shift: Bool
}

public enum Keyboard {
    private static let leads = ["r","R","s","e","E","f","a","q","Q","t","T","d","w","W","c","z","x","v","g"]
    private static let vowels = ["k","o","i","O","j","p","u","P","h","hk","ho","hl","y","n","nj","np","nl","b","m","ml","l"]
    private static let tails = ["","r","R","rt","s","sw","sg","e","f","fr","fa","fq","ft","fx","fv","fg","a","q","qt","t","T","d","w","c","z","x","v","g"]
    private static let jamo: [String: String] = Dictionary(uniqueKeysWithValues:
        zip(Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎㅏㅐㅑㅒㅓㅔㅕㅖㅛㅠㅜㅣ"),
            ["r","R","s","e","E","f","a","q","Q","t","T","d","w","W","c","z","x","v","g","k","o","i","O","j","p","u","P","y","b","n","l"])
            .map { (String($0.0), $0.1) }
    ).merging(["ㅗ":"h","ㅡ":"m","ㄳ":"rt","ㄵ":"sw","ㄶ":"sg","ㄺ":"fr","ㄻ":"fa","ㄼ":"fq","ㄽ":"ft","ㄾ":"fx","ㄿ":"fv","ㅀ":"fg","ㅄ":"qt","ㅘ":"hk","ㅙ":"ho","ㅚ":"hl","ㅝ":"nj","ㅞ":"np","ㅟ":"nl","ㅢ":"ml"]) { _, new in new }
    private static let codes: [String: UInt16] = [
        "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,
        "q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,
        "=":24,"9":25,"7":26,"-":27,"8":28,"0":29,
        "]":30,"o":31,"u":32,"[":33,"i":34,"p":35,"\n":36,"l":37,"j":38,"'":39,"k":40,";":41,
        "\\":42,",":43,"/":44,"n":45,"m":46,".":47,"\t":48," ":49,"`":50
    ]
    private static let shifted = ["!":"1","@":"2","#":"3","$":"4","%":"5","^":"6","&":"7","*":"8","(":"9",
                                  ")":"0","_":"-","+":"=","{":"[","}":"]",":":";","\"":"'","|":"\\","<":",",">":".","?":"/","~":"`"]

    public static func rawKeys(for text: String) -> String {
        text.precomposedStringWithCanonicalMapping.unicodeScalars.map { scalar in
            if (0xAC00...0xD7A3).contains(scalar.value) {
                let n = Int(scalar.value - 0xAC00)
                return leads[n / 588] + vowels[(n / 28) % 21] + tails[n % 28]
            }
            let value = String(scalar)
            return jamo[value] ?? value
        }.joined()
    }

    public static func strokes(for text: String) throws -> [KeyStroke] {
        try rawKeys(for: text).map { character in
            let value = String(character)
            let base = shifted[value] ?? value.lowercased()
            guard let code = codes[base] else { throw KeyboardError.unsupported(value) }
            return KeyStroke(character: value == "\n" ? "\r" : value, base: base,
                             code: code, shift: shifted[value] != nil || value != value.lowercased())
        }
    }
}

public enum KeyboardError: LocalizedError {
    case unsupported(String)
    public var errorDescription: String? {
        switch self { case .unsupported(let value): return "현재 버전에서 자동 타이핑할 수 없는 문자 ‘\(value)’가 있습니다. 문장을 수정해 주세요." }
    }
}
