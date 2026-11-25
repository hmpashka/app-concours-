namespace Loupedeck.GroomPixPlugin
{
    using System;
    using System.Collections.Generic;

    /// Les boutons ronds et carrés : une action de Groom Pix chacun. Marchent même si Groom Pix n'est pas devant.
    public class BoutonsGroomPix : PluginDynamicCommand
    {
        // nom de l'ordre (et pas), libellé dans le logiciel Loupedeck, texte sur la touche
        private static readonly (String ordre, Int32 pas, String libelle, String gros, String petit)[] Liste =
        {
            ("valider", 1, "Valider la série (Entrée)", "✓", "VALIDER"),
            ("ignorer", 1, "Ignorer la série (Échap)", "✕", "IGNORER"),
            ("annuler", 1, "Annuler (⌘Z)", "↶", "ANNULER"),
            ("pause", 1, "Pause / reprendre les envois", "❚❚", "PAUSE"),
            ("rush", 1, "Rush : tout envoyer", "RUSH", "TOUT ENVOYER"),
            ("changerCode", 1, "Changer le code de la photo", "#", "CODE"),
            ("serie", -1, "Série précédente", "▲", "SÉRIE"),
            ("serie", 1, "Série suivante", "▼", "SÉRIE"),
            ("photo", -1, "Photo précédente", "◀", "PHOTO"),
            ("photo", 1, "Photo suivante", "▶", "PHOTO"),
            ("classe.bonne", 1, "Bonne (B)", "B", "BONNE"),
            ("classe.floue", 1, "Floue (F)", "F", "FLOUE"),
            ("classe.sol", 1, "Sol (S)", "S", "SOL"),
            ("classe.code", 1, "Photo de code (C)", "C", "CODE"),
            ("meilleure", 1, "Meilleure (M)", "M", "MEILLEURE"),
            ("reseaux", 1, "Réseaux (R)", "R", "RÉSEAUX"),
            ("chute", 1, "Chute (X)", "X", "CHUTE"),
            ("supprimer", 1, "Supprimer / retirer (⌫)", "⌫", "SUPPRIMER"),
            ("ecran.accueil", 1, "Écran Accueil", "1", "ACCUEIL"),
            ("ecran.aValider", 1, "Écran À valider", "2", "À VALIDER"),
            ("ecran.revue", 1, "Écran Revue", "3", "REVUE"),
            ("ecran.memoire", 1, "Écran Mémoire", "4", "MÉMOIRE"),
            ("ecran.commandes", 1, "Écran Commandes", "5", "COMMANDES"),
            ("ecran.messages", 1, "Écran Messages", "6", "MESSAGES"),
            ("cloture", 1, "Clôturer la journée…", "7", "CLÔTURE"),
            ("panneaux", 1, "Afficher / masquer les panneaux", "8", "PANNEAUX"),
            ("messageLu", 1, "Message lu (efface l'alerte)", "✉", "LU"),
        };

        private readonly Dictionary<String, Int32> _index = new Dictionary<String, Int32>();

        public BoutonsGroomPix() : base()
        {
            for (var i = 0; i < Liste.Length; i++)
            {
                var cle = Cle(i);
                _index[cle] = i;
                this.AddParameter(cle, Liste[i].libelle, "Groom Pix · Boutons");
            }
        }

        private static String Cle(Int32 i) => Liste[i].pas == 1 ? Liste[i].ordre : $"{Liste[i].ordre}{Liste[i].pas:+0;-0}";

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

        protected override void RunCommand(String actionParameter)
        {
            if (GroomPix.Etat == null || !_index.TryGetValue(actionParameter, out var i)) return;
            GroomPix.Envoyer(Liste[i].ordre, Liste[i].pas);
        }

        protected override BitmapImage GetCommandImage(String actionParameter, PluginImageSize imageSize)
        {
            var e = GroomPix.Etat;
            if (!_index.TryGetValue(actionParameter, out var i)) return null;
            var t = Liste[i];
            if (e == null) return Dessin.Touche(imageSize, t.gros, t.petit, Dessin.Genre.Eteint);
            var genre = Dessin.Genre.Normal;
            var gros = t.gros;
            var petit = t.petit;
            switch (t.ordre)
            {
                case "pause":
                    if (e.pause) { gros = "▶"; petit = "REPRENDRE"; genre = Dessin.Genre.Attention; }
                    else genre = Dessin.Genre.Or;
                    break;
                case "rush":
                    genre = e.aValider > 0 ? Dessin.Genre.Erreur : Dessin.Genre.Eteint;
                    break;
                case "ecran.aValider":
                    if (e.aValider > 0) genre = Dessin.Genre.Attention;
                    break;
                case "ecran.messages":
                case "messageLu":
                    if (e.nonLus > 0) genre = Dessin.Genre.Attention;
                    break;
                case "valider":
                    genre = Dessin.Genre.Ok;
                    break;
            }
            return Dessin.Touche(imageSize, gros, petit, genre);
        }
    }
}
