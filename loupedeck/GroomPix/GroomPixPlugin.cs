namespace Loupedeck.GroomPixPlugin
{
    using System;

    /// Module Groom Pix pour le Loupedeck CT : pilote l'app Mac Groom Pix et affiche l'état du stand.
    /// Pas lié à une app au premier plan : les touches marchent même quand Lightroom est devant.
    public class GroomPixPlugin : Plugin
    {
        public override Boolean UsesApplicationApiOnly => true;

        public override Boolean HasNoApplication => true;

        public override void Load() => GroomPix.Demarrer();

        public override void Unload() => GroomPix.Arreter();
    }
}
