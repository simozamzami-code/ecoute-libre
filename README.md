# Sonora pour iPhone

Version native SwiftUI pour iOS 16 ou plus récent. Elle reprend la recherche YouTube, les playlists publiques ou non répertoriées, les favoris locaux et le lecteur audio de Sonora Android.

## État de la livraison

**Le fichier `Sonora-a-signer.ipa` a été compilé pour un vrai iPhone le 3 octobre 2026.** Il est non signé et nécessite AltStore Classic pour l’installation depuis Windows. Aucun Mac personnel n’est nécessaire.

La [compilation GitHub](https://github.com/simozamzami-code/ecoute-libre/actions/runs/37127034927) utilise le commit `77965906c42e5f8ca7254b9e05c0e84844cf684c`. Les quatre tests de base ont réussi : liens YouTube, rejet des liens invalides, conservation des favoris/playlists et affichage des durées. L’archive IPA a été téléchargée et son empreinte vérifiée.

Un contrôle réseau depuis le PC a obtenu un flux AAC audio/mp4 et 1 024 octets avec une réponse HTTP 206. Ce contrôle utilise la même requête mobile YouTube que l’application, mais ne remplace pas une écoute dans AVPlayer sur iPhone. La capture d’écran et les tests réseau supplémentaires du simulateur GitHub ont atteint leur limite de temps ; ils ne sont pas validés, malgré le statut global vert du workflow. L’installation, l’écoute écran verrouillé et l’enchaînement restent à vérifier sur un vrai iPhone.

Empreinte SHA-256 de l’IPA : `fabf1b5ef35ef457e67787b25dfbcb34e746d73f6f7aa6ba1af3b6aa6910fdb6`.

## Fonctionnement prévu

- Recherche YouTube avec chargement de pages supplémentaires.
- Import et conservation des liens de playlists ; actualisation des titres à leur ouverture.
- Ajout et retrait de favoris enregistrés sur l’iPhone.
- Audio seul au format AAC/M4A, compatible avec AVPlayer. Aucun lecteur vidéo n’est chargé.
- Lecture en arrière-plan et commandes sur l’écran verrouillé grâce à AVAudioSession et MediaPlayer.
- Préparation du titre suivant dans AVQueuePlayer pour permettre l’enchaînement en arrière-plan.
- Lecture aléatoire, répétition, file d’écoute, déplacement dans le titre et choix de la sortie AirPlay.
- Pause lors du débranchement des écouteurs et gestion des interruptions audio.

Les flux publicitaires séparés de YouTube ne sont pas demandés. Les sponsors intégrés dans le contenu ne sont pas retirés. L’accès YouTube est non officiel et peut casser lorsque le service évolue. Les directs, contenus privés, comptes Google, téléchargements hors ligne et synchronisation avec Android ne sont pas inclus. L’import s’effectue en collant le lien dans Sonora ; cette version n’ajoute pas d’extension au menu de partage iOS.

## Installer depuis Windows, sans posséder de Mac

La construction et la signature sont deux étapes distinctes :

1. Le projet est placé dans un dépôt GitHub choisi par son propriétaire. Le workflow `.github/workflows/ios.yml` utilise un Mac GitHub pour compiler, exécuter les tests et produire **Sonora-a-signer.ipa**. Aucun identifiant Apple n’est nécessaire à cette étape.
2. L’IPA est ensuite signé et installé depuis Windows avec **AltStore Classic / AltServer**, à l’aide du compte Apple de l’utilisateur.

Un fichier IPA non signé ne s’installe pas directement depuis Safari ou l’application Fichiers. Ne renommer ni l’APK Android ni cette archive de sources en `.ipa` : ce ne sont pas des applications iOS compilées.

### Récupérer la compilation

Après envoi du projet dans le dépôt GitHub :

1. Ouvrir l’onglet **Actions**.
2. Choisir **Construire Sonora pour iPhone**, puis **Run workflow** si la compilation n’a pas déjà démarré.
3. Attendre que les tests et la compilation terminent avec succès.
4. Télécharger l’artefact **Sonora-iPhone**, le décompresser et récupérer `Sonora-a-signer.ipa`.

Le workflow utilise uniquement un accès en lecture au dépôt, ne publie pas de version App Store et conserve les artefacts sept jours. Les dépôts publics bénéficient des runners standards gratuits ; un dépôt privé utilise le quota et éventuellement la facturation de son compte. Vérifier le budget du compte avant de lancer des exécutions payantes.

### Signer et installer

Suivre le [guide officiel AltStore pour Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows), notamment pour les versions compatibles d’iTunes et iCloud.

1. Installer AltServer et les composants demandés par son guide officiel.
2. Brancher l’iPhone au PC, le déverrouiller et approuver la relation de confiance.
3. Installer AltStore Classic sur l’iPhone via AltServer. Saisir le compte Apple directement dans l’outil, jamais dans le code ni dans GitHub.
4. Activer le mode Développeur sur l’iPhone si demandé.
5. Transférer l’IPA dans Fichiers sur l’iPhone, puis l’importer avec le bouton **+** de **My Apps** dans AltStore Classic.
6. Garder AltServer accessible pour la signature et les actualisations nécessaires.

Avec un compte Apple gratuit, les profils personnels expirent après sept jours. L’application doit être actualisée régulièrement via AltStore/AltServer. Le PC n’a pas besoin de rester allumé pour écouter après l’installation, mais il intervient dans ce renouvellement. Il ne s’agit pas d’une publication App Store ni d’une installation permanente sans renouvellement.

## Vérifier sur l’iPhone

Après une compilation réussie et l’installation :

1. Chercher un titre, lancer l’audio et vérifier que le flux est lisible.
2. Importer une playlist, charger la suite et lancer plusieurs titres.
3. Verrouiller l’iPhone, attendre la fin d’un titre et vérifier l’enchaînement.
4. Essayer pause/reprise et suivant depuis l’écran verrouillé.
5. Essayer les écouteurs/Bluetooth et une interruption par un appel.
6. Fermer puis rouvrir l’application pour vérifier la conservation des favoris.

La compilation seule ne valide pas l’extraction YouTube ni le comportement matériel d’iOS.

## Ouvrir sur un Mac

Le projet utilise XcodeGen pour générer le projet Xcode :

```sh
brew install xcodegen
xcodegen generate
open Sonora.xcodeproj
```

Choisir son équipe Apple dans les paramètres de signature pour une installation directe depuis Xcode. Le workflow GitHub effectue la même génération automatiquement puis compile sans certificat personnel.

## Architecture

- `App/YouTubeRepository.swift` : catalogue, pagination, sélection audio AAC et cache temporaire des URLs.
- `App/AudioPlayer.swift` : lecteur, préchargement, session audio et commandes système.
- `App/LibraryStore.swift` : favoris et playlists locales.
- `App/ContentView.swift` : interface SwiftUI.
- `Tests/SonoraTests.swift` : validation des liens, stockage et formatage des durées.
- `project.yml` : cible iOS et dépendance YouTubeKit épinglée à un commit.

## Références

- [Lecture en arrière-plan Apple](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback)
- [Compte Apple personnel et limite de sept jours](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [AltStore Classic sur Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [Actualisation des apps AltStore](https://faq.altstore.io/altstore-classic/your-altstore)
- [Runners GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [YouTubeKit](https://github.com/b5i/YouTubeKit)

Code Sonora sous licence MIT. Les avis de licence tiers sont inclus dans l’application. Sonora n’est pas un produit officiel YouTube, Google ou Apple.
