namespace Loupedeck.GroomPixPlugin
{
    using System;
    using System.Collections.Generic;

    /// Les molettes (et la grande roue) : tourner = un cran dans Groom Pix, appuyer = revenir au départ.
    public class MolettesGroomPix : PluginDynamicAdjustment
    {
        private static readonly (String cle, String ordre, String appui, String libelle)[] Liste =
        {
            ("photo", "photo", "photo.premiere", "Photo précédente / suivante (appui : première)"),
            ("serie", "serie", "serie.ouvrir", "Série à valider (appui : la première)"),
            ("ecran", "ecran", "ecran.accueil", "Écran de l'app (appui : Accueil)"),
            ("epreuve", "epreuve", "epreuve.toutes", "Épreuve de la revue (appui : toutes)"),
            ("filtre", "filtre", "filtre.toutes", "Filtre de la revue (appui : Toutes)"),
            ("zoom", "zoom", "zoom.ajuster", "Zoom sur la photo (appui : ajuster)"),
            ("roue", "photo", "messageLu", "Grande roue : défiler les photos + messages"),
        };

        private readonly Dictionary<String, Int32> _index = new Dictionary<String, Int32>();
        private Int32 _cumul;
        private DateTime _dernierEnvoi = DateTime.MinValue;

        public MolettesGroomPix() : base(true)
        {
            for (var i = 0; i < Liste.Length; i++)
            {
                _index[Liste[i].cle] = i;
                this.AddParameter(Liste[i].cle, Liste[i].libelle, "Groom Pix · Molettes");
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

        private void SurChange(Object sender, EventArgs e)
        {
            this.AdjustmentValueChanged();
            this.ActionImageChanged();
        }

        protected override void ApplyAdjustment(String actionParameter, Int32 diff)
        {
            if (GroomPix.Etat == null || !_index.TryGetValue(actionParameter, out var i) || diff == 0) return;
            if (actionParameter == "roue")
            {
                // la roue envoie beaucoup de crans : on les regroupe (au plus ~20 envois par seconde)
                _cumul += diff;
                if ((DateTime.Now - _dernierEnvoi).TotalMilliseconds < 50) return;
                diff = _cumul;
                _cumul = 0;
                _dernierEnvoi = DateTime.Now;
            }
            GroomPix.Envoyer(Liste[i].ordre, diff);
        }

        protected override void RunCommand(String actionParameter)
        {
            if (GroomPix.Etat == null || !_index.TryGetValue(actionParameter, out var i)) return;
            var e = GroomPix.Etat;
            if (actionParameter == "roue")
            {
                // appui sur la roue : un message à lire → l'écran Messages ; sinon rien
                if (e.message != null) { GroomPix.Envoyer("message"); GroomPix.Envoyer("messageLu"); }
                return;
            }
            GroomPix.Envoyer(Liste[i].appui);
        }

        protected override String GetAdjustmentValue(String actionParameter)
        {
            var e = GroomPix.Etat;
            if (e == null) return "fermé";
            switch (actionParameter)
            {
                case "photo":
                case "roue":
                    if (e.revue != null) return $"{e.revue.position}/{e.revue.total}";
                    if (e.serie != null) return $"{e.serie.position}/{e.serie.total}";
                    return "";
                case "serie": return e.serie != null ? $"{e.serie.position}/{e.serie.total}" : $"{e.series}";
                case "ecran": return NomEcran(e.ecran);
                case "epreuve": return e.revue == null ? "" : (String.IsNullOrEmpty(e.revue.epreuve) ? "toutes" : e.revue.epreuve);
                case "filtre": return e.revue?.filtre ?? "";
                case "zoom": return e.revue == null ? "" : $"×{e.revue.zoom:0.##}";
                default: return "";
            }
        }

        private static String NomEcran(String ecran)
        {
            switch (ecran)
            {
                case "aValider": return "À valider";
                case "revue": return "Revue";
                case "memoire": return "Mémoire";
                case "messages": return "Messages";
                case "commandes": return "Commandes";
                case "reglages": return "Réglages";
                default: return "Accueil";
            }
        }

        /// Image de la molette ; pour la grande roue : le message non lu, sinon la photo affichée avec son code.
        protected override BitmapImage GetAdjustmentImage(String actionParameter, PluginImageSize imageSize)
        {
            if (actionParameter != "roue") return null;
            var e = GroomPix.Etat;
            using var b = new BitmapBuilder(imageSize);
            if (e == null)
            {
                Dessin.Remplir(b, "GP", "fermé", Dessin.Genre.Eteint);
                return b.ToImage();
            }
            var w = b.Width;
            var h = b.Height;
            if (e.message != null)
            {
                var (fond, texte) = Dessin.Couleurs(e.message.incident ? Dessin.Genre.Erreur : Dessin.Genre.Attention);
                b.Clear(fond);
                var qui = String.IsNullOrEmpty(e.message.piste) ? e.message.qui : $"{e.message.qui} · {e.message.piste}";
                b.DrawText(qui, w / 10, h * 14 / 100, w * 8 / 10, h * 16 / 100, Dessin.Creme, Math.Max(10, h / 11));
                var t = e.message.texte.Length > 70 ? e.message.texte.Substring(0, 70) + "…" : e.message.texte;
                b.DrawText(t, w / 8, h * 32 / 100, w * 6 / 8, h * 46 / 100, texte, Math.Max(10, h / 10));
                b.DrawText("appuie : lire", w / 4, h * 78 / 100, w / 2, h * 10 / 100, Dessin.Or, Math.Max(8, h / 16));
                return b.ToImage();
            }
            var code = e.revue?.code ?? e.serie?.proposition ?? "";
            var photo = e.photo.HasValue ? GroomPix.Photo(e.photo.Value) : null;
            if (photo != null)
            {
                b.SetBackgroundImage(photo);
            }
            else
            {
                b.Clear(Dessin.Nuit);
            }
            if (code.Length > 0)
            {
                b.FillRectangle(0, h * 70 / 100, w, h * 30 / 100, new BitmapColor(0, 0, 0, 190));
                b.DrawText(code.TrimStart('#'), 0, h * 70 / 100, w, h * 20 / 100, Dessin.Or, Math.Max(12, h / 7));
            }
            else if (photo == null)
            {
                Dessin.Remplir(b, e.aValider > 0 ? $"{e.aValider}" : "GP", e.aValider > 0 ? "À VALIDER" : "", e.aValider > 0 ? Dessin.Genre.Attention : Dessin.Genre.Normal);
            }
            return b.ToImage();
        }
    }
}
