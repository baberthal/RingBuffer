import PackageDescription

let package = Package(
    name: "RingBuffer",
    targets: [
        Target(name: "Libc", dependencies: []),
        Target(name: "RingBuffer", dependencies: ["Libc"])
    ],
    exclude: ["Makefile", "docs/*", "README.md"]
)
