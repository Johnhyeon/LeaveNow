import Foundation

/// Resources/Secrets.plist 에서 비밀 값을 읽는다. 파일이 없거나 값이 비어 있으면 nil.
enum Secrets {
    static let seoulOpenAPIKey: String? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let key = dict["SeoulOpenAPIKey"] as? String,
              !key.isEmpty, key != "YOUR_KEY_HERE" else { return nil }
        return key
    }()
}
