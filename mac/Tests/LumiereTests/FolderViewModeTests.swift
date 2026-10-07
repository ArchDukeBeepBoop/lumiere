import Foundation
import TestKit
import LumiereKit

/// One preference string holding a mode per library.
@MainActor
func registerFolderViewModeTests(_ t: TestRunner) {

    t.suite("Folder view mode") { t in

        t.test("a library with no stored mode shows icons") {
            t.expectEqual(FolderViewMode.mode(for: "lib", in: ""), .icon)
            t.expectEqual(FolderViewMode.mode(for: "lib", in: "other=list"), .icon)
        }

        t.test("a stored mode is read back") {
            let stored = FolderViewMode.setting(.column, for: "lib", in: "")
            t.expectEqual(FolderViewMode.mode(for: "lib", in: stored), .column)
        }

        t.test("setting one library leaves the others alone") {
            var stored = FolderViewMode.setting(.list, for: "a", in: "")
            stored = FolderViewMode.setting(.column, for: "b", in: stored)
            stored = FolderViewMode.setting(.icon, for: "a", in: stored)
            t.expectEqual(FolderViewMode.mode(for: "a", in: stored), .icon)
            t.expectEqual(FolderViewMode.mode(for: "b", in: stored), .column)
        }

        t.test("a library is never stored twice") {
            var stored = FolderViewMode.setting(.list, for: "a", in: "")
            stored = FolderViewMode.setting(.column, for: "a", in: stored)
            t.expectEqual(stored.split(separator: ",").count, 1)
        }

        t.test("an unreadable preference falls back rather than failing") {
            // A mode this build does not know, and a pair with no value at all.
            t.expectEqual(FolderViewMode.mode(for: "lib", in: "lib=gallery"), .icon)
            t.expectEqual(FolderViewMode.mode(for: "lib", in: "lib"), .icon)
        }
    }
}

/// Matching a whole studio, not a substring of one.
@MainActor
func registerStudioFilterTests(_ t: TestRunner) {

    t.suite("Studio filter") { t in

        t.test("the needle is wrapped in the separator the column joins on") {
            // "Bones" must not match a library whose studio is "Bones Inc", which
            // is the whole reason the column is newline-joined rather than a
            // comma list someone could reasonably search with LIKE.
            t.expectEqual(LibraryRepository.studioPattern("Bones"), "%\nBones\n%")
        }

        t.test("a studio name is escaped, because it is data") {
            // LIKE reads these; a studio called "100%" would otherwise match
            // everything, and one with an underscore would match a wildcard.
            t.expectEqual(LibraryRepository.studioPattern("100%"), "%\n100\\%\n%")
            t.expectEqual(LibraryRepository.studioPattern("a_b"), "%\na\\_b\n%")
        }
    }
}
