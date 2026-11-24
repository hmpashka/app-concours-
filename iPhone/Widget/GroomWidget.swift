// Widget de l'écran verrouillé et de la Dynamic Island : le direct de la piste (Live Activity).
// Mis à jour par l'app quand elle est ouverte, et par le Mac (service d'Apple) quand elle est fermée.
import ActivityKit
import SwiftUI
import TriPhotoCommun
import WidgetKit

@main
struct GroomWidgets: WidgetBundle {
    var body: some Widget { DirectPisteActivite() }
}

struct DirectPisteActivite: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GroomAttributs.self) { ctx in
            VueEcranVerrouille(nom: ctx.attributes.nom, e: ctx.state)
                .activityBackgroundTint(CouleursEcran.nuitFonce.opacity(0.92))
                .activitySystemActionForegroundColor(CouleursEcran.creme)
        } dynamicIsland: { ctx in
            let e = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(e.code.isEmpty ? e.piste : e.code).font(.system(size: 22, weight: .heavy).width(.condensed).italic())
                        .foregroundStyle(CouleursEcran.or)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if e.engages > 0 {
                        Text("\(e.partis)/\(e.engages)").font(.system(size: 18, weight: .bold).width(.condensed))
                            .foregroundStyle(CouleursEcran.creme)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(e.cavalier.isEmpty ? e.titreEpreuve : e.cavalier).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let a = e.alerte {
                            Text("CHANGE TON CODE : \(a)").font(.system(size: 15, weight: .heavy)).foregroundStyle(CouleursEcran.orange)
                        }
                        if e.engages > 0 { ProgressView(value: e.avancement).tint(CouleursEcran.or) }
                        HStack {
                            Text(e.cheval).lineLimit(1)
                            Spacer()
                            Text(e.texteFin)
                        }
                        .font(.system(size: 12)).foregroundStyle(CouleursEcran.cremeDiscret)
                    }
                }
            } compactLeading: {
                Text(e.alerte != nil ? "⚠︎" : (e.code.isEmpty ? "GP" : e.code))
                    .font(.system(size: 14, weight: .heavy).width(.condensed))
                    .foregroundStyle(e.alerte != nil ? CouleursEcran.orange : CouleursEcran.or)
            } compactTrailing: {
                if e.engages > 0 {
                    ProgressView(value: e.avancement).progressViewStyle(.circular).tint(CouleursEcran.or).frame(width: 18)
                } else {
                    Text(e.piste.prefix(2)).font(.system(size: 12, weight: .bold))
                }
            } minimal: {
                if e.alerte != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(CouleursEcran.orange)
                } else {
                    ProgressView(value: e.avancement).progressViewStyle(.circular).tint(CouleursEcran.or)
                }
            }
            .keylineTint(CouleursEcran.or)
        }
    }
}
