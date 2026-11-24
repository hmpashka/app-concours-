import AudioToolbox
import SwiftUI
import TriPhotoCommun

/// Écran principal (maquette « Piste, direct ») : épreuve, fin estimée, ton code en piste, précédent / suivant,
/// photos à renvoyer, tes photos du jour, bouton INCIDENT. L'alerte « CHANGE TON CODE » passe par-dessus.
struct DirectView: View {
    @EnvironmentObject var liaison: Liaison
    @State private var montrerMessages = false
    @State private var montrerRenvoyer = false
    @State private var changerPiste = false
    @State private var incident: Date?
    /// Alerte touchée « C'est changé » : pas remontrée tant que le Mac ne la renvoie pas pour une nouvelle photo.
    @State private var alerteVue: (AlerteCodePiste, Date)?

    private var d: DirectPiste? { liaison.direct }

    private var alerte: AlerteCodePiste? {
        guard let a = d?.alerte else { return nil }
        if let vue = alerteVue, vue.0 == a, Date().timeIntervalSince(vue.1) < 15 { return nil }
        return a
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            entete
            EtatLienView()
            ScrollView {
                VStack(spacing: 14) {
                    epreuve
                    enPiste
                    precedentSuivant
                    if let d, !d.aRenvoyer.isEmpty { aRenvoyer(d) }
                    if let d, !d.info.isEmpty {
                        Text(d.info).font(.system(size: 13)).foregroundStyle(Style.orangeClair)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Text("Mes photos aujourd'hui : ").foregroundColor(Style.cremeDiscret)
                            + Text((d?.mesPhotos ?? 0).formatted()).fontWeight(.semibold)
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 4)
                }
            }
            boutonIncident
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)
        .sheet(isPresented: $montrerMessages) { MessagesPisteView() }
        .sheet(isPresented: $montrerRenvoyer) { RenvoyerView() }
        .sheet(isPresented: $changerPiste) {
            ZStack { Style.fond; ChoixPisteView(fermer: { changerPiste = false }) }.foregroundStyle(Style.creme)
        }
        .fullScreenCover(item: Binding(get: { alerte.map(AlerteAffichee.init) }, set: { _ in })) { a in
            AlerteCodeView(alerte: a.alerte) {
                alerteVue = (a.alerte, Date())
                liaison.alerteVue(a.alerte)
            }
        }
        .onChange(of: d?.alerte) { a in if a == nil { alerteVue = nil } }
    }

    // MARK: - Morceaux

    private var entete: some View {
        HStack {
            Menu {
                Button("Changer de piste") { changerPiste = true }
                Button("Ce n'est pas moi (\(liaison.nom))") { liaison.piste = ""; liaison.nom = "" }
                Toggle("Garder l'écran allumé", isOn: $liaison.ecranAllume)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(liaison.nom) · \(liaison.piste) ▾").font(Style.titre(22)).foregroundStyle(Style.creme)
                    Text([d?.carriere ?? "", liaison.connecte ? "Tri-photo connecté" : "Tri-photo pas joint"]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Style.cremeDiscret)
                }
            }
            Spacer()
            Button { montrerMessages = true } label: {
                Image(systemName: "bubble.left").font(.system(size: 18)).foregroundStyle(Style.creme)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if liaison.nonLus > 0 {
                            Text("\(liaison.nonLus)").font(.system(size: 11, weight: .bold)).foregroundStyle(Style.nuit)
                                .frame(minWidth: 18, minHeight: 18).background(Style.or, in: Capsule()).offset(x: 2, y: -2)
                        }
                    }
            }
        }
    }

    private var epreuve: some View {
        Bloc {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.map { $0.epreuve.isEmpty ? "Pas d'épreuve en cours" : "#\($0.epreuve)\($0.nomEpreuve.isEmpty ? "" : " · \($0.nomEpreuve)")" }
                         ?? "En attente du Mac…")
                        .font(.system(size: 15, weight: .semibold))
                    if let d, d.engages > 0 {
                        Text("\(d.partis) partis sur \(d.engages)").font(.system(size: 12)).foregroundStyle(Style.cremeDiscret)
                    } else if let d, !d.chronoOK {
                        Text("Chrono pas joint par le Mac").font(.system(size: 12)).foregroundStyle(Style.cremeDiscret)
                    }
                }
                Spacer()
                if let f = d?.finEstimee {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Fin estimée").font(.system(size: 11)).foregroundStyle(Style.cremeDiscret)
                        Text(Date(timeIntervalSince1970: f).formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 20, weight: .bold)).monospacedDigit()
                    }
                }
            }
        }
    }

    private var enPiste: some View {
        Bloc(bord: Style.or.opacity(0.45), fond: .white.opacity(0.08), rayon: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("EN PISTE · TON CODE").font(.system(size: 11, weight: .semibold)).tracking(1.1).foregroundStyle(Style.cremeDiscret)
                if let p = d?.enPiste {
                    Text(p.code).font(.system(size: 60, weight: .semibold).width(.condensed)).monospacedDigit()
                        .foregroundStyle(Style.or).minimumScaleFactor(0.6).lineLimit(1)
                    Text(p.cavalier).font(.system(size: 20, weight: .semibold))
                    if !p.cheval.isEmpty { Text(p.cheval).font(.system(size: 15)).foregroundStyle(Style.cremeDiscret) }
                } else {
                    Text("—").font(.system(size: 60, weight: .semibold).width(.condensed)).foregroundStyle(Style.or)
                    Text("Personne en piste pour le moment").font(.system(size: 15)).foregroundStyle(Style.cremeDiscret)
                }
            }
        }
    }

    private var precedentSuivant: some View {
        HStack(spacing: 10) {
            Bloc {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PRÉCÉDENT").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Style.cremeDiscret)
                    Text(d?.precedent?.code ?? "—").font(.system(size: 15, weight: .bold)).monospacedDigit()
                    if let n = d?.precedent?.photos {
                        Text(n == 0 ? "aucune photo" : "\(n) photo\(n > 1 ? "s" : "")").font(.system(size: 12))
                            .foregroundStyle(n == 0 ? Style.orangeClair : Style.cremeDiscret)
                    }
                }
            }
            Bloc {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SUIVANT").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Style.cremeDiscret)
                    Text(d?.suivant?.code ?? "—").font(.system(size: 15, weight: .bold)).monospacedDigit()
                    if let s = d?.suivant { Text(s.cavalier).font(.system(size: 12)).foregroundStyle(Style.cremeDiscret).lineLimit(1) }
                }
            }
        }
    }

    private func aRenvoyer(_ d: DirectPiste) -> some View {
        Button { montrerRenvoyer = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(d.aRenvoyer.count) photo\(d.aRenvoyer.count > 1 ? "s" : "") à renvoyer")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Style.orangeClair)
                    Text(d.aRenvoyer.prefix(4).map { ($0.nom as NSString).deletingPathExtension }.joined(separator: ", "))
                        .font(.system(size: 12)).foregroundStyle(Style.orangeClair.opacity(0.8)).lineLimit(1)
                }
                Spacer()
                Text("›").font(.system(size: 24)).foregroundStyle(Style.orangeClair)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Style.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Style.orange, lineWidth: 1))
        }
    }

    private var boutonIncident: some View {
        VStack(spacing: 8) {
            if let t = incident {
                // l'incident est déjà parti : on peut préciser (ou annuler) d'un toucher
                HStack(spacing: 8) {
                    Text("Noté à \(t.formatted(date: .omitted, time: .standard))").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    ForEach(["Chute", "Refus", "Annuler"], id: \.self) { p in
                        Button(p) {
                            let h = t.formatted(date: .omitted, time: .standard)
                            liaison.envoyer(message: p == "Annuler" ? "Incident de \(h) annulé (erreur)" : "Incident de \(h) : \(p.lowercased())")
                            incident = nil
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.12), in: Capsule())
                    }
                }
                .transition(.opacity)
            }
            Button {
                let t = Date()
                liaison.incident(t)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation { incident = t }
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) { if incident == t { withAnimation { incident = nil } } }
            } label: {
                VStack(spacing: 2) {
                    Text("INCIDENT").font(Style.titre(28)).tracking(1)
                    Text("Marque ce moment (chute, refus…)").font(.system(size: 12)).foregroundStyle(Color(white: 0.93))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 76)
                .background(Style.rouge, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

/// Pour présenter l'alerte en plein écran (il faut un élément identifiable).
struct AlerteAffichee: Identifiable {
    let alerte: AlerteCodePiste
    var id: String { alerte.boitier + alerte.ancien + alerte.attendu }
}

/// Maquette « Piste, alerte code » : vibration et son jusqu'au toucher.
struct AlerteCodeView: View {
    let alerte: AlerteCodePiste
    let vu: () -> Void
    @Environment(\.dismiss) private var fermer
    private let minuterie = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private func epreuve(_ code: String) -> String {
        CodePassage.lire(code).map { "#" + $0.epreuve } ?? code
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Style.rouge, Color(red: 0.45, green: 0.1, blue: 0.08)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("CHANGE TON CODE").font(Style.titre(44)).foregroundStyle(.white)
                (Text("L'épreuve ") + Text(epreuve(alerte.attendu)).bold()
                    + Text(" a commencé sur ta piste, mais tes photos portent encore le code de l'épreuve ")
                    + Text(epreuve(alerte.ancien)).bold() + Text("."))
                    .font(.system(size: 17)).foregroundStyle(.white.opacity(0.92))
                HStack(spacing: 12) {
                    carte("TES PHOTOS", alerte.ancien, barre: true)
                    Text("→").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    carte("À METTRE", alerte.attendu, barre: false)
                }
                if alerte.photos > 0 {
                    Text("Pas de souci pour les \(alerte.photos) photo\(alerte.photos > 1 ? "s" : "") déjà prise\(alerte.photos > 1 ? "s" : "") : Tri-photo propose de les corriger.")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Button {
                    vu()
                    fermer()
                } label: {
                    Text("C'est changé").font(.system(size: 22, weight: .bold)).foregroundStyle(Style.rouge)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                }
                Text("Vibration et son jusqu'au toucher · revient si le code ne change pas")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity)
            }
            .padding(22)
        }
        .onAppear(perform: sonner)
        .onReceive(minuterie) { _ in sonner() }
    }

    private func carte(_ titre: String, _ code: String, barre: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(.white.opacity(0.75))
            Text(code).font(.system(size: 34, weight: .semibold).width(.condensed)).monospacedDigit()
                .strikethrough(barre).foregroundStyle(barre ? .white.opacity(0.7) : .white)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(barre ? 0.10 : 0.22), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sonner() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        AudioServicesPlaySystemSound(1005)
    }
}
