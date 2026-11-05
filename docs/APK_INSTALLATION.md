# APK qui ne s'installe pas — causes et solution

## Cause la plus probable (corrigée dans le workflow)
Chaque build GitHub Actions signait l'APK avec une **clé de debug créée au hasard sur le serveur**.
Android refuse d'installer un APK dont la signature diffère de celle de l'application déjà présente
(« Application non installée » / « conflit avec un package existant »). De plus, le numéro de version
restait toujours `1`, donc Android refusait aussi la mise à jour.

## Correctif appliqué
* `--build-number=${{ github.run_number }}` : le numéro de version augmente à chaque build.
* Signature avec **votre clé permanente** (étape « Signer l'APK » du workflow).

## À faire UNE SEULE FOIS (sur ordinateur, ou via Codespaces/Termux)
1. Créer la clé (gardez le fichier et les mots de passe en lieu sûr — si vous les perdez, plus de mises à jour possibles) :
   `keytool -genkey -v -keystore haitiket.jks -alias haitiket -keyalg RSA -keysize 2048 -validity 10000`
2. Encoder en base64 : `base64 -w0 haitiket.jks`
3. GitHub → Settings → Secrets and variables → Actions → New repository secret :
   * `ANDROID_KEYSTORE_BASE64` = le texte base64
   * `ANDROID_KEYSTORE_PASSWORD` = le mot de passe
   * `ANDROID_KEY_ALIAS` = `haitiket`
4. Relancer le workflow « Build HAITIKET », puis télécharger l'APK dans Releases → `apk-latest`.
5. **Désinstaller une dernière fois** l'ancienne version du téléphone, puis installer la nouvelle.

## Autres causes possibles
* « Installer des applications inconnues » non autorisé pour le navigateur/gestionnaire de fichiers (Paramètres → Applications → Accès spécial).
* Téléchargement incomplet : retélécharger l'APK (taille > 20 Mo).
* Google Play Protect : choisir « Installer quand même ».
* Téléphone 32 bits très ancien ou Android < 5.0.
* Message exact à me transmettre si le problème continue (capture de l'erreur).
