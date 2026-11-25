namespace Loupedeck.GroomPixPlugin
{
    using System;

    /// Couleurs de Groom Pix (bleu nuit et or) et dessin d'une touche : un gros chiffre ou mot, un petit rappel dessous.
    /// Les touches du CT font environ 1,5 cm : jamais plus de deux lignes.
    public static class Dessin
    {
        public static readonly BitmapColor Nuit = new BitmapColor(14, 42, 71);
        public static readonly BitmapColor Or = new BitmapColor(201, 163, 74);
        public static readonly BitmapColor Creme = new BitmapColor(245, 241, 232);
        public static readonly BitmapColor Orange = new BitmapColor(110, 66, 16);
        public static readonly BitmapColor OrangeTexte = new BitmapColor(255, 194, 120);
        public static readonly BitmapColor Vert = new BitmapColor(27, 74, 50);
        public static readonly BitmapColor VertTexte = new BitmapColor(139, 224, 173);
        public static readonly BitmapColor Rouge = new BitmapColor(122, 35, 28);
        public static readonly BitmapColor RougeTexte = new BitmapColor(255, 184, 174);
        public static readonly BitmapColor OrFonce = new BitmapColor(74, 61, 31);
        public static readonly BitmapColor Gris = new BitmapColor(40, 42, 46);
        public static readonly BitmapColor GrisTexte = new BitmapColor(130, 134, 140);

        public enum Genre { Normal, Attention, Ok, Erreur, Or, Eteint }

        public static BitmapImage Touche(PluginImageSize taille, String gros, String petit, Genre genre = Genre.Normal)
        {
            using var b = new BitmapBuilder(taille);
            Remplir(b, gros, petit, genre);
            return b.ToImage();
        }

        public static void Remplir(BitmapBuilder b, String gros, String petit, Genre genre)
        {
            var (fond, texte) = Couleurs(genre);
            b.Clear(fond);
            var w = b.Width;
            var h = b.Height;
            // taille du gros texte selon sa longueur
            var n = Math.Max(1, gros?.Length ?? 1);
            var police = n <= 2 ? h * 42 / 100 : n <= 4 ? h * 30 / 100 : n <= 6 ? h * 22 / 100 : h * 16 / 100;
            if (String.IsNullOrEmpty(petit))
            {
                b.DrawText(gros ?? "", 0, 0, w, h, texte, police);
            }
            else
            {
                b.DrawText(gros ?? "", 0, h * 6 / 100, w, h * 64 / 100, texte, police);
                b.DrawText(petit, 0, h * 66 / 100, w, h * 28 / 100, genre == Genre.Normal ? Or : texte, Math.Max(9, h * 13 / 100));
            }
        }

        public static (BitmapColor fond, BitmapColor texte) Couleurs(Genre g)
        {
            switch (g)
            {
                case Genre.Attention: return (Orange, OrangeTexte);
                case Genre.Ok: return (Vert, VertTexte);
                case Genre.Erreur: return (Rouge, RougeTexte);
                case Genre.Or: return (OrFonce, Or);
                case Genre.Eteint: return (Gris, GrisTexte);
                default: return (Nuit, Creme);
            }
        }

        /// Groom Pix fermé ou pont coupé : touche grise.
        public static BitmapImage Ferme(PluginImageSize taille, String petit = "fermé") => Touche(taille, "GP", petit, Genre.Eteint);

        /// « Quartz du Bois » → « Quartz »
        public static String Court(String s, Int32 max = 8)
        {
            if (String.IsNullOrWhiteSpace(s)) return "";
            var mot = s.Trim().Split(' ')[0];
            return mot.Length <= max ? mot : mot.Substring(0, max);
        }
    }
}
