// swift-tools-version:5.9
// Tri-photo, la vraie app Mac.
//
// - TriPhotoCommun : ce qui servira aussi à l'app iPhone Piste (fichier FFE, codes #épreuve_dossard).
// - TriPhotoMoteur : le moteur photos (réception, .cube, IPTC, Lightroom), sans interface.
// - TriPhotoMac    : l'app Mac elle-même (fenêtres, menus, réglages, accueil, mode entraînement).
// - essai-moteur   : essai du moteur en ligne de commande, sur un dossier de photos (vitesse, original intact).
// - essai-piste    : fait comme un iPhone de l'app Piste, pour essayer le lien avec le Mac sans iPhone.
// - iPhone/Piste.swiftpm : l'app iPhone Piste (à ouvrir dans Xcode).
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
        .executable(name: "essai-piste", targets: ["essai-piste"]),
    ],
    targets: [
        .target(name: "TriPhotoCommun"),
        .target(name: "TriPhotoMoteur", dependencies: ["TriPhotoCommun"]),
        .executableTarget(name: "TriPhotoMac", dependencies: ["TriPhotoCommun", "TriPhotoMoteur"]),
        .executableTarget(name: "essai-moteur", dependencies: ["TriPhotoCommun", "TriPhotoMoteur"]),
        .executableTarget(name: "essai-piste", dependencies: ["TriPhotoCommun"]),
        .testTarget(
            name: "TriPhotoCommunTests",
            dependencies: ["TriPhotoCommun"],
            resources: [.copy("Donnees")]
        ),
    ]
)
