# Sourced by the icon scripts (needs $ROOT). render_svg <in.svg> <out.png> <width> <height>
render_svg() {
    tool="${TMPDIR:-/tmp}/sstl-render-svg"
    if [ ! -x "$tool" ] || [ "$ROOT/scripts/render-svg.swift" -nt "$tool" ]; then
        swiftc -O "$ROOT/scripts/render-svg.swift" -o "$tool"
    fi
    "$tool" "$@"
}
