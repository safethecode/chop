import Foundation

public struct GitHubRepository: Equatable, Sendable {
  public let owner: String
  public let name: String
  public let cloneAddress: String

  public init(_ input: String) throws {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.hasPrefix("/") else { throw GitCloneError.invalidRepository }
    var path = value
    var useSSH = false
    if value.hasPrefix("git@github.com:") {
      path = String(value.dropFirst("git@github.com:".count))
      useSSH = true
    } else if value.contains("://") {
      guard let parts = URLComponents(string: value),
        parts.host?.lowercased() == "github.com", parts.password == nil,
        (parts.scheme?.lowercased() == "https" && parts.user == nil && parts.port == nil)
          || (parts.scheme?.lowercased() == "ssh" && parts.user == "git"
            && (parts.port == nil || parts.port == 22))
      else { throw GitCloneError.invalidRepository }
      path = parts.path
      useSSH = parts.scheme?.lowercased() == "ssh"
    } else if value.hasPrefix("github.com/") {
      path = String(value.dropFirst("github.com/".count))
    }
    path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if path.hasSuffix(".git") { path.removeLast(4) }
    let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
    guard pieces.count == 2,
      pieces[0].range(of: #"^[A-Za-z0-9][A-Za-z0-9-]{0,38}$"#, options: .regularExpression) != nil,
      pieces[1].range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
      pieces[1] != ".", pieces[1] != "..", pieces[1].utf8.count <= 100
    else { throw GitCloneError.invalidRepository }
    owner = String(pieces[0])
    name = String(pieces[1])
    cloneAddress =
      useSSH ? "git@github.com:\(owner)/\(name).git" : "https://github.com/\(owner)/\(name).git"
  }
}

public enum GitCloneError: Error, LocalizedError, Equatable {
  case invalidRepository, invalidFolderName, invalidParent, destinationExists, unavailableGit,
    failed

  public var errorDescription: String? {
    switch self {
    case .invalidRepository:
      "GitHub 저장소 주소 또는 owner/repo 형식으로 입력해 주세요."
    case .invalidFolderName:
      "폴더 이름을 줄이고 /, :와 줄바꿈을 빼 주세요."
    case .invalidParent:
      "저장할 폴더를 다시 선택해 주세요."
    case .destinationExists:
      "같은 이름의 항목이 있어요. 폴더 이름이나 저장 위치를 바꿔 주세요."
    case .unavailableGit:
      "Git을 실행하지 못했어요. macOS 개발자 도구 설치 상태를 확인해 주세요."
    case .failed:
      "클론하지 못했어요. 저장소 주소와 이 Mac의 Git 접근 권한을 확인해 주세요."
    }
  }

  public static func validateFolderName(_ name: String) throws {
    guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255,
      !name.contains("/"), !name.contains(":"),
      !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { throw GitCloneError.invalidFolderName }
  }
}
