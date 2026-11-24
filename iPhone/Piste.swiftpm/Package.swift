// swift-tools-version: 5.9
// App iPhone « Piste » de Groom Pix (étape 3). À ouvrir dans Xcode (double-clic sur Piste.swiftpm),
// choisir son équipe (compte développeur Apple) dans « Signing & Capabilities », brancher l'iPhone, puis ▶︎.
//
// Elle partage TriPhotoCommun avec l'app Mac (les messages échangés sur le wifi, les codes).
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Piste",
    platforms: [.iOS("16.0")],
    products: [
        .iOSApplication(
            name: "Groom Pix Piste",
            targets: ["AppModule"],
            bundleIdentifier: "fr.hmtimings.piste",
            teamIdentifier: "",
            displayVersion: "0.4",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.yellow),
            supportedDeviceFamilies: [.phone],
            supportedInterfaceOrientations: [.portrait],
            capabilities: [
                .localNetwork(purposeString: "L'app Piste trouve le Mac Groom Pix sur le wifi du concours.",
                              bonjourServiceTypes: ["_triphoto._tcp"])
            ],
            appCategory: .photography
        )
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            dependencies: [.product(name: "TriPhotoCommun", package: "app-concours-")],
            path: ".",
            resources: [.copy("Polices")]
        )
    ]
)
