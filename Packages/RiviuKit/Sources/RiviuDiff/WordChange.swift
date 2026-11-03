/// Finds the part of a line that changed, so it can be highlighted more strongly than the rest of the line.
public enum WordChange {
    /// Returns the changed middle of each line (UTF-16 offsets) after trimming the shared prefix and suffix.
    /// Returns nil when the lines are identical or almost entirely different, where a highlight adds nothing.
    public static func changedRanges(old: String, new: String) -> (old: Range<Int>, new: Range<Int>)? {
        let a = Array(old.utf16)
        let b = Array(new.utf16)
        let shorter = min(a.count, b.count)

        var prefix = 0
        while prefix < shorter && a[prefix] == b[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < shorter - prefix && a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
            suffix += 1
        }

        let oldRange = prefix..<(a.count - suffix)
        let newRange = prefix..<(b.count - suffix)
        if oldRange.isEmpty && newRange.isEmpty {
            return nil
        }
        let mostlyRewritten = Double(oldRange.count) > Double(a.count) * 0.8 && Double(newRange.count) > Double(b.count) * 0.8
        return mostlyRewritten ? nil : (oldRange, newRange)
    }
}
