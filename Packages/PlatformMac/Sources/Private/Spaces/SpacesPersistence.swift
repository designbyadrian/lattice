import Foundation
import LayoutModel

/// Application Support helpers for workspace↔Space binding persistence.
public enum SpacesPersistence {
    public static let appSupportFolderName = "Lattice"
    public static let bindingFileName = "workspace-space-binding.json"

    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(appSupportFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static func bindingFileURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent(bindingFileName, isDirectory: false)
    }

    public static func loadBinding(fileManager: FileManager = .default) -> WorkspaceSpaceBinding {
        do {
            let url = try bindingFileURL(fileManager: fileManager)
            guard fileManager.fileExists(atPath: url.path) else {
                return WorkspaceSpaceBinding()
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(WorkspaceSpaceBinding.self, from: data)
        } catch {
            return WorkspaceSpaceBinding()
        }
    }

    public static func saveBinding(
        _ binding: WorkspaceSpaceBinding,
        fileManager: FileManager = .default
    ) {
        do {
            let url = try bindingFileURL(fileManager: fileManager)
            let data = try JSONEncoder().encode(binding)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Best-effort; caller keeps in-memory state.
        }
    }
}
