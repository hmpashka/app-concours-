namespace Loupedeck.GroomPixPlugin
{
    using System;
    using System.Collections.Generic;
    using System.Net.Http;
    using System.Text.Json;
    using System.Threading;
    using System.Threading.Tasks;

    // Ce que Groom Pix envoie (même forme que EtatLoupedeck dans PontLoupedeck.swift).
    public class EtatGP
    {
        public Int32 version { get; set; }
        public String concours { get; set; } = "";
        public Boolean actif { get; set; }
        public String ecran { get; set; } = "accueil";
        public Boolean pause { get; set; }
        public Int32 aValider { get; set; }
        public Int32 series { get; set; }
        public Int32 aReprendre { get; set; }
        public Int32 enFile { get; set; }
        public Double retardSecondes { get; set; }
        public Double parMinute { get; set; }
        public Int32 recues { get; set; }
        public Int32 enErreur { get; set; }
        public List<ChronoGP> chronos { get; set; } = new List<ChronoGP>();
        public String galerie { get; set; } = "aucune";
        public Int32 galerieAFaire { get; set; }
        public List<PisteGP> pistes { get; set; } = new List<PisteGP>();
        public List<String> alertes { get; set; } = new List<String>();
        public RevueGP revue { get; set; }
        public SerieGP serie { get; set; }
        public MessageGP message { get; set; }
        public Int32 nonLus { get; set; }
        public Int64? photo { get; set; }
    }

    public class ChronoGP { public String nom { get; set; } = ""; public Boolean? ok { get; set; } }

    public class PisteGP
    {
        public String piste { get; set; } = "";
        public String code { get; set; } = "";
        public String cavalier { get; set; } = "";
        public String cheval { get; set; } = "";
        public Boolean termine { get; set; }
    }

    public class RevueGP
    {
        public Int32 position { get; set; }
        public Int32 total { get; set; }
        public String code { get; set; } = "";
        public String cavalier { get; set; } = "";
        public String cheval { get; set; } = "";
        public String classe { get; set; } = "";
        public Boolean meilleure { get; set; }
        public Boolean reseaux { get; set; }
        public Boolean chute { get; set; }
        public String filtre { get; set; } = "";
        public String ordre { get; set; } = "";
        public String epreuve { get; set; } = "";
        public Boolean suppressionPermise { get; set; }
        public Double zoom { get; set; }
    }

    public class SerieGP
    {
        public Int32 position { get; set; }
        public Int32 total { get; set; }
        public String code { get; set; } = "";
        public String proposition { get; set; } = "";
        public Int32 photos { get; set; }
        public Boolean photoCode { get; set; }
    }

    public class MessageGP
    {
        public String id { get; set; } = "";
        public String qui { get; set; } = "";
        public String piste { get; set; } = "";
        public String texte { get; set; } = "";
        public Double heure { get; set; }
        public Boolean incident { get; set; }
    }

    /// Journal de diagnostic : /tmp/groompix-loupedeck.log (≈ 200 Ko au plus). Erreurs et « répond / ne répond plus ».
    public static class Journal
    {
        private const String Chemin = "/tmp/groompix-loupedeck.log";
        private static readonly Object _v = new Object();

        public static void Ecrire(String texte)
        {
            try
            {
                lock (_v)
                {
                    var f = new System.IO.FileInfo(Chemin);
                    if (f.Exists && f.Length > 200_000) f.Delete();
                    System.IO.File.AppendAllText(Chemin, $"{DateTime.Now:HH:mm:ss.fff} {texte}\n");
                }
            }
            catch
            {
            }
        }
    }

    /// Le lien avec Groom Pix : http://127.0.0.1:8095 (ce Mac seulement). L'état est lu une fois par seconde
    /// (≈ 1 Ko) ; les boutons partent tout de suite. Si Groom Pix est fermé, Etat vaut null et les touches sont grises.
    public static class GroomPix
    {
        private const String Adresse = "http://127.0.0.1:8095";
        private static readonly HttpClient Client = Creer();
        private static Timer _minuterie;
        private static String _dernier = "";
        private static readonly Object _verrou = new Object();
        private static readonly Dictionary<Int64, BitmapImage> _photos = new Dictionary<Int64, BitmapImage>();
        private static readonly HashSet<Int64> _enCours = new HashSet<Int64>();
        private static readonly System.Text.RegularExpressions.Regex HeureJson =
            new System.Text.RegularExpressions.Regex("\"heure\":[0-9.eE+-]+");
        private static readonly JsonSerializerOptions Options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };

        /// Dernier état reçu, null si Groom Pix ne répond pas.
        public static EtatGP Etat { get; private set; }

        /// Appelé quand l'état a changé (les touches se redessinent).
        public static event EventHandler Change;

        private static HttpClient Creer()
        {
            var c = new HttpClient { Timeout = TimeSpan.FromMilliseconds(900) };
            c.DefaultRequestHeaders.Add("X-Groom-Pix", "1");
            return c;
        }

        public static void Demarrer()
        {
            Journal.Ecrire("Demarrer");
            if (_minuterie != null) return;
            _minuterie = new Timer(_ => _ = Lire(), null, 0, 1000);
        }

        public static void Arreter()
        {
            _minuterie?.Dispose();
            _minuterie = null;
        }

        private static async Task Lire()
        {
            String texte;
            try
            {
                texte = await Client.GetStringAsync(Adresse + "/etat").ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                if (Etat != null) Journal.Ecrire("Lire /etat : " + ex.GetType().Name + " : " + ex.Message + (ex.InnerException != null ? " / " + ex.InnerException.Message : ""));
                texte = "";
            }
            // l'heure change à chaque lecture : on l'ignore pour ne redessiner que si quelque chose a vraiment changé
            var comparable = HeureJson.Replace(texte, "");
            lock (_verrou)
            {
                if (comparable == _dernier) return;
                _dernier = comparable;
            }
            EtatGP e = null;
            if (texte.Length > 0)
            {
                try { e = JsonSerializer.Deserialize<EtatGP>(texte, Options); }
                catch (Exception ex) { Journal.Ecrire("JSON : " + ex.Message); e = null; }
            }
            if ((e == null) != (Etat == null)) Journal.Ecrire(e == null ? "Groom Pix ne répond plus" : $"état reçu (écran {e.ecran})");
            Etat = e;
            Change?.Invoke(null, EventArgs.Empty);
        }

        /// Un bouton ou une molette : « photo » pas +1, « classe.bonne »…
        public static void Envoyer(String nom, Int32 pas = 1)
        {
            _ = Task.Run(async () =>
            {
                try
                {
                    using var r = await Client.PostAsync($"{Adresse}/action/{nom}?pas={pas}", null).ConfigureAwait(false);
                }
                catch
                {
                    return;
                }
                await Task.Delay(120).ConfigureAwait(false);
                await Lire().ConfigureAwait(false);
            });
        }

        /// Vignette carrée de la photo (pour l'écran de la roue). null tant qu'elle n'est pas arrivée.
        public static BitmapImage Photo(Int64 id)
        {
            lock (_verrou)
            {
                if (_photos.TryGetValue(id, out var img)) return img;
                if (_enCours.Contains(id)) return null;
                _enCours.Add(id);
            }
            _ = Task.Run(async () =>
            {
                try
                {
                    var octets = await Client.GetByteArrayAsync($"{Adresse}/photo/{id}").ConfigureAwait(false);
                    var img = BitmapImage.FromArray(octets);
                    lock (_verrou)
                    {
                        if (_photos.Count > 20) _photos.Clear();
                        _photos[id] = img;
                    }
                    Change?.Invoke(null, EventArgs.Empty);
                }
                catch
                {
                }
                finally
                {
                    lock (_verrou) { _enCours.Remove(id); }
                }
            });
            return null;
        }
    }
}
