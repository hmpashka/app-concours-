#if canImport(Network)
import Foundation
import Network

/// Une connexion Mac ↔ iPhone : envoie et reçoit des messages (une ligne de JSON chacun).
/// Les rappels arrivent sur la file principale.
public final class Canal<Recu: Decodable, Envoye: Encodable>: @unchecked Sendable {
    public let id = UUID()
    public let connexion: NWConnection
    private let file = DispatchQueue(label: "tri-photo.canal", qos: .utility)
    private var trames = Trames()
    private var ferme = false

    /// Un message reçu.
    public var recu: ((Recu) -> Void)?
    /// Connexion prête (vrai) ou perdue (faux, une seule fois).
    public var etat: ((Bool) -> Void)?

    public init(_ connexion: NWConnection) {
        self.connexion = connexion
    }

    public func demarrer() {
        connexion.stateUpdateHandler = { [weak self] e in
            guard let self else { return }
            switch e {
            case .ready:
                DispatchQueue.main.async { self.etat?(true) }
            case .failed, .cancelled:
                self.fermer()
            case .waiting:
                // réseau absent : on abandonne, l'iPhone relance tout seul
                self.fermer()
            default: break
            }
        }
        connexion.start(queue: file)
        lire()
    }

    public func envoyer(_ v: Envoye) {
        guard !ferme, let d = Trames.encoder(v) else { return }
        connexion.send(content: d, completion: .contentProcessed { [weak self] erreur in
            if erreur != nil { self?.fermer() }
        })
    }

    public func fermer() {
        file.async { [weak self] in
            guard let self, !self.ferme else { return }
            self.ferme = true
            self.connexion.cancel()
            DispatchQueue.main.async { self.etat?(false) }
        }
    }

    private func lire() {
        connexion.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, fini, erreur in
            guard let self else { return }
            if let data, !data.isEmpty {
                let messages = self.trames.recevoir(data, comme: Recu.self)
                if !messages.isEmpty { DispatchQueue.main.async { messages.forEach { self.recu?($0) } } }
            }
            if fini || erreur != nil { self.fermer(); return }
            self.lire()
        }
    }

    /// Réglages TCP : petits messages envoyés tout de suite, connexion morte détectée en ~20 s.
    public static var parametres: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 2
        let p = NWParameters(tls: nil, tcp: tcp)
        p.includePeerToPeer = false
        return p
    }
}
#endif
