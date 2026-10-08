/* ============================================================
   CONFIGURATION DU SITE — L'Objectif Châlonnais
   C'est le seul fichier à modifier pour personnaliser le site.
   ============================================================ */
window.OC_CONFIG = {

  // ---------- Réseaux sociaux ----------
  // ⚠️ À VÉRIFIER : ces adresses sont supposées, remplace-les par vos vraies.
  // Laisse '' pour masquer un réseau.
  reseaux: {
    tiktok:    'https://www.tiktok.com/@lobjectifchalonn',
    instagram: 'https://www.instagram.com/lobjectifchalonnais',
    youtube:   'https://www.youtube.com/@lobjectifchalonnais',
    facebook:  ''   // à remettre quand la page sera réactivée
  },

  // ---------- Contact ----------
  contact: 'lobjectifchalonnais@gmail.com',

  // ---------- Soutenir l'association ----------
  // Lien vers la page HelloAsso (ou autre). Laisse '' pour masquer le bouton.
  dons: '',

  // ---------- Base de données partagée (Supabase, gratuit) ----------
  // Sans ces deux valeurs, le site fonctionne mais :
  //  - les bons plans ajoutés restent sur l'appareil de chaque visiteur,
  //  - les inscriptions à la newsletter ne sont pas enregistrées.
  // Avec ces deux valeurs, tout le monde voit les mêmes bons plans.
  // Mode d'emploi complet dans le fichier LISEZMOI.md.
  supabaseUrl: 'https://inszwlresrlsboqaedjm.supabase.co',      // ex. 'https://abcdefgh.supabase.co'
  supabaseCle: 'sb_publishable_40XFyoJFG6Mef-1rZbHJyg_wK8__QN4'       // la clé « publishable » ou « anon public » (jamais la clé secrète)
};
