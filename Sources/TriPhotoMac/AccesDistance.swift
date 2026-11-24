import Foundation
import ImageIO
import Network
import TriPhotoCommun
import TriPhotoMoteur
import UniformTypeIdentifiers

/// Ce que la page à distance montre du tableau de bord (rien d'autre ne sort du Mac).
struct EtatDistance: Codable {
    struct Boitier: Codable { var nom: String; var photos: Int; var derniere: Double? }
    struct Piste: Codable { var piste: String; var epreuve: String; var dossard: String; var cavalier: String; var cheval: String; var termine: Bool }
    struct Epreuve: Codable { var numero: String; var nom: String }
    var concours: String
    var actif: Bool
    var recues: Int
    var parMinute: Double
    var enFile: Int
    var retardSecondes: Double
    var aValider: Int
    var aRenvoyer: Int
    var dansTampon: Int
    var enErreur: Int
    var chrono: String
    var galerie: String
    var boitiers: [Boitier]
    var pistes: [Piste]
    var alertes: [String]
    var epreuves: [Epreuve]
    var heure: Double
}

/// Une photo de la revue à distance.
struct PhotoDistance: Codable {
    var id: Int64
    var nom: String
    var code: String
    var cavalier: String
    var cheval: String
    var prise: Double?
    var classe: String
    var chute: Bool
}

/// Accès à distance depuis un autre Mac ou un PC : une page web en LECTURE SEULE (tableau de bord et revue des
/// photos), servie par Tri-photo sur le réseau du stand. Aucun réglage, aucune action : on regarde seulement.
/// Protégée par un code (Réglages › 5. Envois). Les vignettes sont petites (≈ 30 Ko) pour ne pas charger le réseau.
final class AccesDistance: @unchecked Sendable {
    private let file = DispatchQueue(label: "tri-photo.acces-distance", qos: .utility)
    private var ecoute: NWListener?
    private var port = 0
    private let vignettes = NSCache<NSNumber, NSData>()
    /// Fournis par l'app (lus sur le fil principal).
    var code: @MainActor () -> String = { "" }
    var etat: @MainActor () -> EtatDistance? = { nil }
    var moteur: Moteur?

    init() { vignettes.countLimit = 600 }

    var enMarche: Bool { file.sync { ecoute != nil } }

    func demarrer(port p: Int) {
        file.async {
            if self.ecoute != nil && self.port == p { return }
            self.ecoute?.cancel()
            self.ecoute = nil
            guard let np = NWEndpoint.Port(rawValue: UInt16(clamping: p)), let l = try? NWListener(using: .tcp, on: np) else { return }
            l.service = NWListener.Service(name: "Tri-photo", type: "_http._tcp")
            l.newConnectionHandler = { [weak self] c in self?.servir(c) }
            l.stateUpdateHandler = { [weak self] e in
                if case .failed = e { self?.file.async { self?.ecoute?.cancel(); self?.ecoute = nil } }
            }
            l.start(queue: self.file)
            self.ecoute = l
            self.port = p
        }
    }

    func arreter() {
        file.async {
            self.ecoute?.cancel()
            self.ecoute = nil
        }
    }

    /// Adresses où joindre la page (wifi / câble du Mac).
    static func adresses(port: Int) -> [String] {
        var l: [String] = []
        var liste: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&liste) == 0, let premier = liste else { return [] }
        defer { freeifaddrs(liste) }
        var p: UnsafeMutablePointer<ifaddrs>? = premier
        while let i = p {
            let a = i.pointee
            if let adr = a.ifa_addr, adr.pointee.sa_family == UInt8(AF_INET), (a.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 {
                var hote = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(adr, socklen_t(adr.pointee.sa_len), &hote, socklen_t(hote.count), nil, 0, NI_NUMERICHOST) == 0 {
                    l.append("http://\(String(cString: hote)):\(port)")
                }
            }
            p = a.ifa_next
        }
        if let nom = Host.current().localizedName {
            let local = nom.replacingOccurrences(of: " ", with: "-").folding(options: .diacriticInsensitive, locale: nil)
            l.append("http://\(local).local:\(port)")
        }
        return l
    }

    // MARK: - HTTP (le minimum : GET, une réponse, on ferme)

    private func servir(_ c: NWConnection) {
        c.start(queue: file)
        c.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let texte = String(data: data, encoding: .utf8) else { c.cancel(); return }
            self.repondre(texte, sur: c)
        }
        file.asyncAfter(deadline: .now() + 30) { c.cancel() }
    }

    private struct Reponse {
        var code = 200
        var type = "text/html; charset=utf-8"
        var corps = Data()
        var entetes: [String: String] = [:]
    }

    private func repondre(_ requete: String, sur c: NWConnection) {
        let lignes = requete.components(separatedBy: "\r\n")
        let morceaux = (lignes.first ?? "").split(separator: " ")
        guard morceaux.count >= 2, morceaux[0] == "GET" else {
            envoyer(Reponse(code: 405, type: "text/plain", corps: Data("Lecture seule".utf8)), sur: c)
            return
        }
        let cible = String(morceaux[1])
        let comps = URLComponents(string: "http://x" + cible)
        let chemin = comps?.path ?? "/"
        let params = Dictionary((comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        var cookie = ""
        for l in lignes where l.lowercased().hasPrefix("cookie:") {
            for m in l.dropFirst(7).split(separator: ";") {
                let kv = m.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 && kv[0] == "tp" { cookie = kv[1] }
            }
        }
        let attendu = DispatchQueue.main.sync { MainActor.assumeIsolated { self.code() } }
        let donne = params["code"] ?? ""
        if !donne.isEmpty && donne == attendu {
            // bon code : retenu une semaine dans le navigateur
            envoyer(Reponse(code: 302, type: "text/plain", entetes: [
                "Location": "/", "Set-Cookie": "tp=\(attendu); Max-Age=604800; Path=/; HttpOnly; SameSite=Strict"]), sur: c)
            return
        }
        guard !attendu.isEmpty, cookie == attendu else {
            envoyer(Reponse(corps: Data(AccesDistance.pageCode(erreur: !donne.isEmpty).utf8)), sur: c)
            return
        }
        switch chemin {
        case "/":
            envoyer(Reponse(corps: Data(AccesDistance.page.utf8)), sur: c)
        case "/api/etat":
            let e = DispatchQueue.main.sync { MainActor.assumeIsolated { self.etat() } }
            let d = (try? JSONEncoder().encode(e)) ?? Data("null".utf8)
            envoyer(Reponse(type: "application/json", corps: d, entetes: ["Cache-Control": "no-store"]), sur: c)
        case "/api/photos":
            let ep = params["epreuve"].flatMap { $0.isEmpty ? nil : $0 }
            let l = (moteur?.photosRevue(epreuve: ep) ?? []).prefix(600).map {
                PhotoDistance(id: $0.id, nom: $0.nom, code: $0.codeRetenu, cavalier: $0.cavalier, cheval: $0.cheval,
                              prise: $0.prise?.timeIntervalSince1970, classe: $0.classe, chute: $0.chute)
            }
            let d = (try? JSONEncoder().encode(Array(l))) ?? Data("[]".utf8)
            envoyer(Reponse(type: "application/json", corps: d, entetes: ["Cache-Control": "no-store"]), sur: c)
        default:
            if chemin.hasPrefix("/vignette/"), let id = Int64(chemin.dropFirst(10)), let d = vignette(id) {
                envoyer(Reponse(type: "image/jpeg", corps: d, entetes: ["Cache-Control": "private, max-age=86400"]), sur: c)
            } else if chemin.hasPrefix("/photo/"), let id = Int64(chemin.dropFirst(7)), let f = moteur?.fiche(id: id),
                      let d = FileManager.default.contents(atPath: f.copie) {
                // la copie du serveur local (déjà compressée) : rien n'est recalculé
                envoyer(Reponse(type: "image/jpeg", corps: d, entetes: ["Cache-Control": "private, max-age=3600"]), sur: c)
            } else {
                envoyer(Reponse(code: 404, type: "text/plain", corps: Data("Introuvable".utf8)), sur: c)
            }
        }
    }

    /// Vignette de 420 px tirée de la copie du serveur local (ou de l'original), gardée en mémoire.
    private func vignette(_ id: Int64) -> Data? {
        if let d = vignettes.object(forKey: NSNumber(value: id)) { return d as Data }
        guard let f = moteur?.fiche(id: id) else { return nil }
        let source = FileManager.default.fileExists(atPath: f.copie) ? f.copie : f.chemin
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 420]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let sortie = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(sortie, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        vignettes.setObject(sortie, forKey: NSNumber(value: id))
        return sortie as Data
    }

    private func envoyer(_ r: Reponse, sur c: NWConnection) {
        let raison = [200: "OK", 302: "Found", 404: "Not Found", 405: "Method Not Allowed"][r.code] ?? "OK"
        var tete = "HTTP/1.1 \(r.code) \(raison)\r\nContent-Type: \(r.type)\r\nContent-Length: \(r.corps.count)\r\nConnection: close\r\n"
        tete += "X-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n"
        for (k, v) in r.entetes { tete += "\(k): \(v)\r\n" }
        tete += "\r\n"
        var d = Data(tete.utf8)
        d.append(r.corps)
        c.send(content: d, completion: .contentProcessed { _ in c.cancel() })
    }

    // MARK: - Pages

    static func pageCode(erreur: Bool) -> String {
        """
        <!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Tri-photo</title><style>
        body{margin:0;background:#1e1e1e;color:#ddd;font:15px -apple-system,Segoe UI,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh}
        form{background:#2a2a2a;border:1px solid #3a3a3a;border-radius:8px;padding:28px;width:300px}
        h1{font-size:18px;margin:0 0 6px}p{color:#999;font-size:13px;margin:0 0 16px}
        input{width:100%;box-sizing:border-box;padding:10px;border-radius:5px;border:1px solid #444;background:#1a1a1a;color:#fff;font-size:18px;letter-spacing:4px;text-align:center}
        button{margin-top:12px;width:100%;padding:10px;border:0;border-radius:5px;background:#2d7ff9;color:#fff;font-size:14px;font-weight:600}
        .e{color:#e66;font-size:13px;margin-top:10px}</style></head><body>
        <form method="get" action="/"><h1>Tri-photo</h1><p>Tableau de bord et revue, en lecture seule. Code dans les réglages de l'app (5. Envois).</p>
        <input name="code" inputmode="numeric" autocomplete="off" autofocus placeholder="Code"><button>Ouvrir</button>
        \(erreur ? "<div class=\"e\">Code incorrect.</div>" : "")</form></body></html>
        """
    }

    static let page = """
    <!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Tri-photo · à distance</title><style>
    :root{--fond:#1e1e1e;--panneau:#262626;--bord:#383838;--texte:#ddd;--discret:#999;--accent:#2d7ff9;--ok:#4cc77a;--att:#e8913a;--err:#e45b5b}
    *{box-sizing:border-box}body{margin:0;background:var(--fond);color:var(--texte);font:14px -apple-system,Segoe UI,sans-serif}
    header{display:flex;align-items:center;gap:20px;padding:12px 20px;background:var(--panneau);border-bottom:1px solid var(--bord);flex-wrap:wrap}
    header h1{font-size:15px;margin:0}header small{color:var(--discret)}nav{display:flex;gap:4px;margin-left:auto}
    nav button{background:none;border:0;color:var(--discret);padding:6px 12px;border-radius:5px;font-size:13px;cursor:pointer}
    nav button.on{background:#3a3f4a;color:#fff;font-weight:600}main{padding:20px;max-width:1400px;margin:0 auto}
    .grille{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:12px}
    .carte{background:var(--panneau);border:1px solid var(--bord);border-radius:8px;padding:14px}
    .carte b{display:block;font-size:24px;font-weight:600;margin-top:4px}.carte span{color:var(--discret);font-size:12px}
    h2{font-size:14px;margin:22px 0 10px}table{width:100%;border-collapse:collapse;background:var(--panneau);border:1px solid var(--bord);border-radius:8px;overflow:hidden}
    td,th{padding:8px 12px;border-bottom:1px solid var(--bord);text-align:left;font-size:13px}th{color:var(--discret);font-weight:500}
    .alerte{background:rgba(232,145,58,.12);border:1px solid var(--att);border-radius:6px;padding:8px 12px;margin-bottom:6px;font-size:13px}
    .photos{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:10px}
    .ph{background:var(--panneau);border:1px solid var(--bord);border-radius:6px;overflow:hidden;cursor:zoom-in}
    .ph img{width:100%;aspect-ratio:3/2;object-fit:cover;display:block;background:#111}.ph div{padding:6px 8px;font-size:12px}
    .ph .c{color:var(--accent);font-weight:600}.ph .n{color:var(--discret);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    select{background:#1a1a1a;color:var(--texte);border:1px solid #444;border-radius:5px;padding:6px 8px;font-size:13px}
    #grand{position:fixed;inset:0;background:rgba(0,0,0,.92);display:none;align-items:center;justify-content:center;cursor:zoom-out;flex-direction:column}
    #grand img{max-width:96vw;max-height:88vh}#grand p{color:#ccc;font-size:13px}.ok{color:var(--ok)}.err{color:var(--err)}
    @media (max-width:600px){main{padding:12px}nav{margin-left:0}}
    </style></head><body>
    <header><div><h1 id="titre">Tri-photo</h1><small id="sous">Lecture seule</small></div>
    <nav><button id="b-tdb" class="on" onclick="voir('tdb')">Tableau de bord</button><button id="b-revue" onclick="voir('revue')">Revue</button></nav></header>
    <main><section id="tdb"><div id="alertes"></div><div class="grille" id="cartes"></div>
    <h2>En piste</h2><table id="pistes"></table><h2>Boîtiers</h2><table id="boitiers"></table></section>
    <section id="revue" hidden><p><select id="ep" onchange="photos()"><option value="">Toutes les épreuves</option></select>
    <span id="nb" style="color:var(--discret);margin-left:10px"></span></p><div class="photos" id="liste"></div></section></main>
    <div id="grand" onclick="this.style.display='none'"><img id="gi" alt=""><p id="gt"></p></div>
    <script>
    const h=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const hm=t=>t?new Date(t*1000).toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit'}):'';
    let eps=false;
    function voir(v){for(const x of['tdb','revue']){document.getElementById(x).hidden=x!==v;document.getElementById('b-'+x).classList.toggle('on',x===v)}if(v==='revue')photos()}
    function carte(t,v,s){return `<div class="carte"><span>${h(t)}</span><b>${h(v)}</b>${s?`<span>${h(s)}</span>`:''}</div>`}
    async function etat(){try{const r=await fetch('/api/etat');if(r.status!==200){location.reload();return}const e=await r.json();if(!e)return;
    document.getElementById('titre').textContent=e.concours||'Tri-photo';
    document.getElementById('sous').innerHTML=(e.actif?'<span class="ok">Tri en cours</span>':'<span class="err">Tri arrêté</span>')+' · '+h(e.chrono)+' · mis à jour '+hm(e.heure);
    document.getElementById('cartes').innerHTML=carte('Photos reçues aujourd\\'hui',e.recues)+carte('Par minute',e.parMinute.toFixed(0))+
    carte('En file',e.enFile,e.retardSecondes>30?'retard '+Math.round(e.retardSecondes)+' s':'')+carte('À valider',e.aValider)+
    carte('À renvoyer',e.aRenvoyer)+carte('Dans le tampon',e.dansTampon)+carte('En erreur',e.enErreur)+carte('Galerie en ligne',e.galerie||'—');
    document.getElementById('alertes').innerHTML=e.alertes.map(a=>`<div class="alerte">${h(a)}</div>`).join('');
    document.getElementById('pistes').innerHTML='<tr><th>Piste</th><th>Épreuve</th><th>Dossard</th><th>Cavalier</th><th>Cheval</th></tr>'+
    (e.pistes.length?e.pistes.map(p=>`<tr><td>${h(p.piste)}</td><td>${h(p.epreuve)}</td><td>${h(p.dossard)}</td><td>${h(p.cavalier)}</td><td>${h(p.cheval)}${p.termine?' <span style="color:var(--discret)">(terminé)</span>':''}</td></tr>`).join(''):'<tr><td colspan="5" style="color:var(--discret)">Pas de chrono, ou rien en piste.</td></tr>');
    document.getElementById('boitiers').innerHTML='<tr><th>Boîtier</th><th>Photos</th><th>Dernière</th></tr>'+e.boitiers.map(b=>`<tr><td>${h(b.nom)}</td><td>${b.photos}</td><td>${hm(b.derniere)}</td></tr>`).join('');
    if(!eps&&e.epreuves.length){eps=true;document.getElementById('ep').innerHTML+=e.epreuves.map(x=>`<option value="${h(x.numero)}">${h(x.nom)}</option>`).join('')}
    }catch(_){}}
    async function photos(){const ep=document.getElementById('ep').value;const r=await fetch('/api/photos?epreuve='+encodeURIComponent(ep));const l=await r.json();
    document.getElementById('nb').textContent=l.length+' photos'+(l.length>=600?' (les 600 dernières)':'');
    document.getElementById('liste').innerHTML=l.map(p=>`<div class="ph" onclick="grand(${p.id},'${h(p.nom)} · ${h(p.code)} · ${h(p.cavalier)} ${h(p.cheval)}')"><img loading="lazy" src="/vignette/${p.id}" alt=""><div><span class="c">${h(p.code)||'sans code'}</span> ${p.chute?'· CHUTE ':''}${p.classe?'· '+h(p.classe):''}<div class="n">${h(p.cavalier)} ${h(p.cheval)}</div><div class="n">${h(p.nom)} · ${hm(p.prise)}</div></div></div>`).join('')}
    function grand(id,t){document.getElementById('gi').src='/photo/'+id;document.getElementById('gt').textContent=t;document.getElementById('grand').style.display='flex'}
    etat();setInterval(()=>{if(!document.hidden)etat()},5000);
    </script></body></html>
    """
}
