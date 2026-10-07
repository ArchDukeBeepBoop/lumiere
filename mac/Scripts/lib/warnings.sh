#!/bin/bash
# The build-warning policy, shared by check.sh and bundle.sh.
#
# It lived only in check.sh, which builds debug — while install.sh ships what
# bundle.sh builds in release. Nothing ever inspected the release build's output,
# so the configuration that actually reaches /Applications was the one configuration
# with no warning gate on it at all. Optimised builds emit diagnostics debug builds
# do not, so that is exactly backwards.
#
# Usage: check_build_warnings "$BUILD_LOG"

# Apple deprecated OpenGL in 10.14 and libmpv's only supported macOS embedding path
# is its OpenGL render API. There is no Metal equivalent to migrate to, so these
# specific deprecations are expected and permanent — in the one file that draws
# video, and nowhere else.
# `glGetString` and friends are here because the allowlist matched only the Cocoa
# and CGL wrappers, never the GL entry points themselves — so a real, permanent,
# expected deprecation in the one file allowed to have them was being reported as an
# unexpected warning. It went unnoticed because the debug build it was gating had
# long since compiled that file and had nothing to say about it.
GL_SYMBOLS="NSOpenGL|MTKView|wantsBestResolutionOpenGLSurface|swapInterval|CGLLockContext|CGLUnlockContext|gl[A-Z][A-Za-z]*"

check_build_warnings() {
	local log="$1"

	# Matched on the deprecated symbol, not on the filename. Swift prints a warning
	# as a `file:line: warning:` header followed by an indented excerpt whose own
	# line repeats the warning and carries the `[#...]` tag — so no single line holds
	# both the filename and the tag, and a `filename.*tag` pattern excludes neither.
	# That is why this looked like a working allowlist for several phases while never
	# actually suppressing anything.
	local unexpected
	unexpected="$(echo "$log" \
		| grep "warning:" \
		| grep -Ev "($GL_SYMBOLS).*was deprecated" \
		|| true)"

	if [ -n "$unexpected" ]; then
		echo "$unexpected"
		echo "FAIL: build produced unexpected warnings" >&2
		return 1
	fi

	# Anything OpenGL-deprecated outside the one file that draws video is a real
	# finding: it means GL has leaked into the rest of the app.
	local stray
	stray="$(echo "$log" \
		| grep -E "warning:.*($GL_SYMBOLS).*was deprecated" \
		| grep -E "^/.*\.swift:" \
		| grep -v "MPVVideoView.swift" \
		|| true)"

	if [ -n "$stray" ]; then
		echo "$stray"
		echo "FAIL: OpenGL deprecation warnings outside MPVVideoView.swift" >&2
		return 1
	fi

	local count
	count="$(echo "$log" | grep -cE "warning:.*($GL_SYMBOLS).*was deprecated" || true)"

	# An incremental build that recompiled nothing emits no warnings, so a clean
	# result proves nothing at all. Both warnings this gate was written to catch
	# were hidden that way — they only appeared once the files were touched. Said
	# out loud rather than silently passing, because "clean" and "did not look"
	# should not print the same line.
	if ! echo "$log" | grep -q "Compiling"; then
		echo "    nothing recompiled — warnings not re-checked (touch a file to force)"
		return 0
	fi

	echo "    clean ($count expected OpenGL deprecation warnings in MPVVideoView.swift)"
}
