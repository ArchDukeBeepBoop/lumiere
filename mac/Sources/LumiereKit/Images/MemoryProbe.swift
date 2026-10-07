import Foundation

/// Reads this process's real memory cost.
///
/// `phys_footprint` is the number that matters: it is what Activity Monitor
/// shows, what the memory-pressure system acts on, and what gets a process
/// jetsammed. Resident size (RSS) is misleading here because it counts shared,
/// clean framework pages that are not this app's cost — on Lumiere the gap is
/// routinely 70 MB.
public enum MemoryProbe {

    /// Bytes. Nil if the kernel refuses, which should not happen for self.
    public static func physFootprint() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return Int(info.phys_footprint)
    }

    public static var megabytes: Double {
        Double(physFootprint() ?? 0) / 1_048_576
    }

    public static func formatted() -> String {
        String(format: "%.0f MB", megabytes)
    }
}
