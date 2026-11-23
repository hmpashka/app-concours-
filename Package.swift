// swift-tools-version:5.9
// Tri-photo, la vraie app Mac (étape 0 : les fondations).
//
// - TriPhotoCommun : ce qui servira aussi à l'app iPhone Piste (fichier FFE, codes #épreuve_dossard).
// - TriPhotoMac    : l'app Mac elle-même (fenêtres, menus, réglages, mode entraînement).
//
// Construire l'app : ./scripts/construire-app.sh   (fabrique « Tri-photo.app » dans le dossier « build »)
// Lancer les tests : swift test
import PackageDescription

let package = Package(
    name: "TriPhoto",
    defaultLocalization: "fr",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "TriPhotoCommun", targets: ["TriPhotoCommun"]),
        .executable(name: "TriPhotoMac", targets: ["TriPhotoMac"]),
    ],
    targets: [
        .target(name: "TriPhotoCommun"),
        .executableTarget(name: "TriPhotoMac", dependencies: ["TriPhotoCommun"]),
        .testTarget(
            name: "TriPhotoCommunTests",
            dependencies: ["TriPhotoCommun"],
            resources: [.copy("Donnees")]
        ),
    ]
)
