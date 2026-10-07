# The 300-line rule, as a ratchet. Shared: LumiereControl's check.sh sources
# this same file, so the two apps cannot drift into different rules.
#
# The rule predates this check, and some files had already outgrown it. Those
# are listed in Scripts/line-budget.txt at the size they were when the check
# arrived: they may shrink, never grow, and a file that shrinks under 300 drops
# off the list for good. Every other file fails above 300 and is warned about
# above 260, so the split happens while there is still room to do it cleanly.
check_line_budget() {
    local root="$1" failed=0 file lines budget
    while IFS= read -r file; do
        lines=$(wc -l < "$root/$file" | tr -d ' ')
        budget=$(awk -v f="$file" '$1 == f { print $2 }' "$root/Scripts/line-budget.txt" 2>/dev/null || true)
        if [ -n "$budget" ]; then
            if [ "$lines" -gt "$budget" ]; then
                echo "  ✗ $file grew to $lines lines (over the 300 rule, budget $budget) — split it"
                failed=1
            fi
        elif [ "$lines" -gt 300 ]; then
            echo "  ✗ $file is $lines lines (limit 300) — split it"
            failed=1
        elif [ "$lines" -gt 260 ]; then
            echo "  ! $file is $lines lines — split before it reaches 300"
        fi
    done < <(cd "$root" && find $(ls -d Sources Tests 2>/dev/null) -name '*.swift' | sort)
    return $failed
}
