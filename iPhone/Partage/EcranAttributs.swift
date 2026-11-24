// Partagé entre l'app et le widget : le bloc Groom Pix de l'écran verrouillé.
// Le contenu (EcranVerrouille) est le même que celui envoyé par le Mac au service d'Apple.
import ActivityKit
import Foundation
import SwiftUI
import TriPhotoCommun

struct GroomAttributs: ActivityAttributes {
    typealias ContentState = EcranVerrouille
    /// Prénom du photographe et piste suivie au lancement.
    var nom: String
    var piste: String
}

/// Couleurs de l'écran verrouillé (thème Bleu et or, comme l'app).
enum CouleursEcran {
    static let nuit = Color(red: 0x0e / 255, green: 0x2a / 255, blue: 0x47 / 255)
    static let nuitFonce = Color(red: 0x08 / 255, green: 0x1a / 255, blue: 0x2e / 255)
    static let creme = Color(red: 0xf5 / 255, green: 0xf1 / 255, blue: 0xe8 / 255)
    static let cremeDiscret = Color(red: 0xc9 / 255, green: 0xc3 / 255, blue: 0xb6 / 255)
    static let or = Color(red: 0xc9 / 255, green: 0xa3 / 255, blue: 0x4a / 255)
    static let orange = Color(red: 0xe8 / 255, green: 0x91 / 255, blue: 0x3a / 255)
}

extension EcranVerrouille {
    var texteFin: String {
        guard let f = finEstimee else { return "" }
        return "Fin ≈ " + Date(timeIntervalSince1970: f).formatted(date: .omitted, time: .shortened)
    }
    var titreEpreuve: String {
        if epreuve.isEmpty { return chronoOK ? "Pas d'épreuve en cours" : "En attente du chrono" }
        return "Ép. \(epreuve)" + (nomEpreuve.isEmpty ? "" : " · \(nomEpreuve)")
    }
}

/// Le bloc complet, sur l'écran verrouillé et dans la Dynamic Island ouverte.
struct VueEcranVerrouille: View {
    let nom: String
    let e: EcranVerrouille

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(e.piste.uppercased()).font(.system(size: 13, weight: .heavy).width(.condensed)).foregroundStyle(CouleursEcran.or)
                Text(e.titreEpreuve).font(.system(size: 13, weight: .semibold)).foregroundStyle(CouleursEcran.cremeDiscret).lineLimit(1)
                Spacer(minLength: 4)
                if e.aRenvoyer > 0 {
                    Label("\(e.aRenvoyer)", systemImage: "arrow.uturn.up").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CouleursEcran.orange)
                }
            }
            if let a = e.alerte {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("CHANGE TON CODE : \(a)").font(.system(size: 17, weight: .heavy).width(.condensed))
                }
                .foregroundStyle(CouleursEcran.orange)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(e.code.isEmpty ? "—" : e.code).font(.system(size: 28, weight: .heavy).width(.condensed).italic())
                    .foregroundStyle(CouleursEcran.or)
                VStack(alignment: .leading, spacing: 0) {
                    Text(e.cavalier.isEmpty ? "Personne en piste" : e.cavalier).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CouleursEcran.creme).lineLimit(1)
                    if !e.cheval.isEmpty {
                        Text(e.cheval).font(.system(size: 13)).foregroundStyle(CouleursEcran.cremeDiscret).lineLimit(1)
                    }
                }
            }
            if e.engages > 0 {
                ProgressView(value: e.avancement).tint(CouleursEcran.or)
                HStack {
                    Text("\(e.partis) / \(e.engages) partis")
                    Spacer()
                    Text(e.texteFin)
                }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(CouleursEcran.cremeDiscret)
            }
            if !e.suivant.isEmpty {
                Text("Ensuite : \(e.suivant)").font(.system(size: 12)).foregroundStyle(CouleursEcran.cremeDiscret).lineLimit(1)
            }
        }
        .padding(14)
    }
}
