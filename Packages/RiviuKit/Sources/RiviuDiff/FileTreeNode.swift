/// A folder or file in the changed-files sidebar.
public struct FileTreeNode: Identifiable, Hashable, Sendable {
    /// The full path; for files this matches `FileDiff.path`.
    public let id: String
    public let name: String
    /// nil for files.
    public let children: [FileTreeNode]?

    public var isFolder: Bool { children != nil }

    /// All folder ids in this subtree, useful for expanding everything by default.
    public var folderIDs: [String] {
        guard let children else { return [] }
        return [id] + children.flatMap(\.folderIDs)
    }

    /// Builds a tree from file paths. Folders come first, and folder chains with a single child are
    /// merged into one row ("crates/diff-core/src") to keep the tree shallow.
    public static func tree(for paths: [String]) -> [FileTreeNode] {
        nodes(for: paths.map { $0.split(separator: "/").map(String.init) }, parentPath: "")
    }

    private static func nodes(for paths: [[String]], parentPath: String) -> [FileTreeNode] {
        let fileNames = paths.filter { $0.count == 1 }.map { $0[0] }
        let pathsByFolder = Dictionary(grouping: paths.filter { $0.count > 1 }, by: { $0[0] })

        var folders: [FileTreeNode] = []
        for (folderName, members) in pathsByFolder {
            var name = folderName
            var path = join(parentPath, folderName)
            var remaining = members.map { Array($0.dropFirst()) }

            while remaining.allSatisfy({ $0.count > 1 }), Set(remaining.map { $0[0] }).count == 1 {
                let onlyChild = remaining[0][0]
                name += "/" + onlyChild
                path = join(path, onlyChild)
                remaining = remaining.map { Array($0.dropFirst()) }
            }
            folders.append(FileTreeNode(id: path, name: name, children: nodes(for: remaining, parentPath: path)))
        }

        let files = fileNames.map { FileTreeNode(id: join(parentPath, $0), name: $0, children: nil) }
        return folders.sorted(by: byName) + files.sorted(by: byName)
    }

    private static func join(_ parent: String, _ name: String) -> String {
        parent.isEmpty ? name : parent + "/" + name
    }

    private static func byName(_ a: FileTreeNode, _ b: FileTreeNode) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
