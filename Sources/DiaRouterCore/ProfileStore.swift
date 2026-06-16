// Sources/DiaRouterCore/ProfileStore.swift
import Foundation

public enum ProfileStore {
    /// Standardpfad zu Dias Local State.
    public static func defaultLocalStatePath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dia/User Data/Local State")
    }

    private struct LocalState: Decodable {
        struct ProfileSection: Decodable {
            struct Info: Decodable { let name: String? }
            let info_cache: [String: Info]
        }
        let profile: ProfileSection
    }

    public static func loadProfiles(localStatePath: URL) throws -> [Profile] {
        let data = try Data(contentsOf: localStatePath)
        let state = try JSONDecoder().decode(LocalState.self, from: data)
        return state.profile.info_cache
            .map { Profile(directory: $0.key, name: $0.value.name ?? $0.key) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
