// swift-tools-version:5.9
// Tri-photo, la vraie app Mac.
//
// - TriPhotoCommun : ce qui servira aussi à l'app iPhone Piste (fichier FFE, codes #épreuve_dossard).
// - TriPhotoMoteur : le moteur photos (réception, .cube, IPTC, Lightroom), sans interface.
// - TriPhotoMac    : l'app Mac elle-même (fenêtres, menus, réglages, accueil, mode entraînement).
// - essai-moteur   : essai du moteur en ligne de commande, sur un dossier de photos (vitesse, original intact).
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
        .executable(name: "essai-moteur", targets: ["essai-moteur"]),
    ],
    targets: [
        .target(name: "TriPhotoCommun"),
        .target(name: "TriPhotoMoteur", dependencies: ["TriPhotoCommun"]),
        .executableTarget(name: "TriPhotoMac", dependencies: ["TriPhotoCommun", "TriPhotoMoteur"]),
        .executableTarget(name: "essai-moteur", dependencies: ["TriPhotoCommun", "TriPhotoMoteur"]),
        .testTarget(
            name: "TriPhotoCommunTests",
            dependencies: ["TriPhotoCommun"],
            resources: [.copy("Donnees")]
        ),
    ]
)
