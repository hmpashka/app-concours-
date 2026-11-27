namespace Loupedeck.GroomPixPlugin
{
    using System;
    using System.Linq;

    /// Les 12 touches de l'écran tactile. Chaque « case » change toute seule selon l'écran de Groom Pix :
    /// page « Direct » (état du stand) ou page « Revue » (classer la photo). Mettre la case 1 en haut à gauche,
    /// la 12 en bas à droite.
    public class CasesEcran : PluginDynamicCommand
    {
        public CasesEcran() : base()
        {
            // « widget » : l'image remplit toute la case et le logiciel n'écrit pas le nom par-dessus
            this.IsWidget = true;
            for (var i = 1; i <= 12; i++)
            {
                this.AddParameter(i.ToString(), $"Case {i:00} de l'écran", "Groom Pix · Écran tactile");
            }
        }

        protected override Boolean OnLoad()
        {
            GroomPix.Change += this.SurChange;
            return true;
        }

        protected override Boolean OnUnload()
        {
            GroomPix.Change -= this.SurChange;
            return true;
        }

        private void SurChange(Object sender, EventArgs e) => this.ActionImageChanged();

        private static Boolean PageRevue(EtatGP e) => e.ecran == "revue" && e.revue != null;

        protected override BitmapImage GetCommandImage(String actionParameter, PluginImageSize imageSize)
        {
            try
            {
                return this.Image(actionParameter, imageSize);
            }
            catch (Exception ex)
            {
                Journal.Ecrire($"image case {actionParameter} : {ex}");
                return null;
            }
        }

        private BitmapImage Image(String actionParameter, PluginImageSize imageSize)
        {
            var e = GroomPix.Etat;
            if (e == null) return Dessin.Ferme(imageSize, actionParameter == "1" ? "fermé" : "");
            var n = Int32.TryParse(actionParameter, out var k) ? k : 0;
            var (gros, petit, genre) = PageRevue(e) ? Revue(e, n) : Direct(e, n);
            return Dessin.Touche(imageSize, gros, petit, genre);
        }

        protected override String GetCommandDisplayName(String actionParameter, PluginImageSize imageSize) => "";

        protected override void RunCommand(String actionParameter)
        {
            var e = GroomPix.Etat;
            if (e == null) return;
            var n = Int32.TryParse(actionParameter, out var k) ? k : 0;
            var ordre = PageRevue(e) ? ActionRevue(n) : ActionDirect(e, n);
            if (ordre != null) GroomPix.Envoyer(ordre);
        }

        // MARK: page Direct

        private static (String, String, Dessin.Genre) Direct(EtatGP e, Int32 n)
        {
            switch (n)
            {
                case 1:
                    return ($"{e.aValider}", "À VALIDER", e.aValider > 0 ? Dessin.Genre.Attention : Dessin.Genre.Normal);
                case 2:
                    return ($"{e.enFile}", e.retardSecondes >= 60 ? $"ENVOIS +{(Int32)(e.retardSecondes / 60)}MIN" : "ENVOIS",
                            e.enErreur > 0 ? Dessin.Genre.Erreur : e.retardSecondes >= 120 ? Dessin.Genre.Attention : Dessin.Genre.Normal);
                case 3:
                {
                    if (e.chronos.Count == 0) return ("—", "CHRONO", Dessin.Genre.Eteint);
                    var ok = e.chronos.Count(c => c.ok == true);
                    var gros = String.Join(" ", e.chronos.Select(c => c.ok == true ? "✓" : c.ok == false ? "✕" : "…"));
                    return (gros, "CHRONOS", ok == e.chronos.Count ? Dessin.Genre.Ok : e.chronos.Any(c => c.ok == false) ? Dessin.Genre.Erreur : Dessin.Genre.Normal);
                }
                case 4:
                    switch (e.galerie)
                    {
                        case "ok": return ("✓", "GALERIE", Dessin.Genre.Ok);
                        case "attente": return ($"{e.galerieAFaire}", "GALERIE", Dessin.Genre.Normal);
                        case "nuit": return ($"{e.galerieAFaire}", "LA NUIT", Dessin.Genre.Normal);
                        case "pause": return ("❚❚", "GALERIE", Dessin.Genre.Or);
                        case "erreur": return ("✕", "GALERIE", Dessin.Genre.Erreur);
                        default: return ("—", "GALERIE", Dessin.Genre.Eteint);
                    }
                case 5:
                case 6:
                case 7:
                case 8:
                {
                    var i = n - 5;
                    if (i >= e.pistes.Count) return ("—", $"PISTE {i + 1}", Dessin.Genre.Eteint);
                    var p = e.pistes[i];
                    var nom = p.piste.Length <= 9 ? p.piste.ToUpperInvariant() : p.piste.Substring(0, 9).ToUpperInvariant();
                    return (String.IsNullOrEmpty(p.code) ? "—" : p.code, nom, p.termine ? Dessin.Genre.Eteint : Dessin.Genre.Normal);
                }
                case 9:
                    return e.aValider > 0 ? ("RUSH", "TOUT ENVOYER", Dessin.Genre.Erreur) : ("RUSH", "À JOUR", Dessin.Genre.Eteint);
                case 10:
                    if (!e.actif) return ("—", "TRI ARRÊTÉ", Dessin.Genre.Eteint);
                    return e.pause ? ("▶", "REPRENDRE", Dessin.Genre.Attention) : ("❚❚", "PAUSE", Dessin.Genre.Or);
                case 11:
                    return ($"{(Int32)Math.Round(e.parMinute)}", "/ MIN", Dessin.Genre.Normal);
                case 12:
                    if (e.message != null)
                        return (Dessin.Court(e.message.qui, 7).ToUpperInvariant(), e.message.incident ? "INCIDENT" : "MESSAGE",
                                e.message.incident ? Dessin.Genre.Erreur : Dessin.Genre.Attention);
                    return e.alertes.Count > 0 ? ($"{e.alertes.Count}", e.alertes.Count > 1 ? "ALERTES" : "ALERTE", Dessin.Genre.Attention)
                                               : ("0", "ALERTE", Dessin.Genre.Normal);
                default:
                    return ("", "", Dessin.Genre.Eteint);
            }
        }

        private static String ActionDirect(EtatGP e, Int32 n)
        {
            switch (n)
            {
                case 1: return "ecran.aValider";
                case 9: return "rush";
                case 10: return "pause";
                case 12: return e.message != null ? "message" : "ecran.accueil";
                default: return "ecran.accueil";
            }
        }

        // MARK: page Revue

        private static (String, String, Dessin.Genre) Revue(EtatGP e, Int32 n)
        {
            var r = e.revue;
            Dessin.Genre Si(Boolean oui, Dessin.Genre g = Dessin.Genre.Ok) => oui ? g : Dessin.Genre.Normal;
            switch (n)
            {
                case 1: return ("B", "BONNE", Si(r.classe == "bonne"));
                case 2: return ("F", "FLOUE", Si(r.classe == "floue", Dessin.Genre.Attention));
                case 3: return ("S", "SOL", Si(r.classe == "sol", Dessin.Genre.Attention));
                case 4: return ("C", "CODE", Si(r.classe == "code", Dessin.Genre.Attention));
                case 5: return ("M", "MEILLEURE", Si(r.meilleure, Dessin.Genre.Or));
                case 6: return ("R", "RÉSEAUX", Si(r.reseaux, Dessin.Genre.Or));
                case 7: return ("X", "CHUTE", Si(r.chute, Dessin.Genre.Erreur));
                case 8:
                    if (r.suppressionPermise) return ("⌫", "SUPPRIMER", Dessin.Genre.Erreur);
                    return r.filtre == "Bonnes" ? ("⌫", "RETIRER", Dessin.Genre.Normal) : ("⌫", "—", Dessin.Genre.Eteint);
                case 9: return (r.total == 0 ? "0" : $"{r.position}/{r.total}", "PHOTO", Dessin.Genre.Normal);
                case 10: return (r.filtre.ToUpperInvariant(), "FILTRE", Dessin.Genre.Normal);
                case 11: return (r.ordre.ToUpperInvariant(), "ORDRE", Dessin.Genre.Normal);
                case 12: return ($"{e.aValider}", "À VALIDER", e.aValider > 0 ? Dessin.Genre.Attention : Dessin.Genre.Normal);
                default: return ("", "", Dessin.Genre.Eteint);
            }
        }

        private static String ActionRevue(Int32 n)
        {
            switch (n)
            {
                case 1: return "classe.bonne";
                case 2: return "classe.floue";
                case 3: return "classe.sol";
                case 4: return "classe.code";
                case 5: return "meilleure";
                case 6: return "reseaux";
                case 7: return "chute";
                case 8: return "supprimer";
                case 9: return "photo.premiere";
                case 10: return "filtre";
                case 11: return "ordre";
                case 12: return "ecran.aValider";
                default: return null;
            }
        }
    }
}
