# AxelL - Linux Optimmisateur

[![Debian 13](https://img.shields.io/badge/Debian-13%20Trixie-A81D33?logo=debian&logoColor=white)](https://www.debian.org/releases/trixie/)
[![Shell](https://img.shields.io/badge/Shell-Bash-121011?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-2ea44f.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.0-1677ff.svg)](linux-optimizer.sh)

Outil d'audit et d'optimisation prudente pour serveurs Linux professionnels. Le projet cible en priorité **Debian 13 (Trixie)** sur des machines qui hébergent Docker, sites web, applications Node.js/Python, Pterodactyl/Wings ou KeyHelp.

> L'objectif est la fiabilite et la lisibilite des changements, pas la promesse de gains universels. Mesurez votre serveur avant et apres chaque modification importante.

## Points forts

- Audit initial en lecture seule avec OS, noyau, RAM, swap, BBR, services et ports en ecoute.
- Splash de demarrage au nom de **AxelL - Linux Optimmisateur** avec licence MIT.
- Progression coloree avec pourcentage, temps ecoule et estimation du temps restant.
- Journal horodate et rapport final dans `/var/log/linux-optimizer/`.
- Configurations idempotentes avec sauvegardes datees.
- Aucune modification automatique du DNS, du fuseau horaire ou des conteneurs.
- Validation de la configuration SSH avant tout rechargement.
- XanMod non installe automatiquement : le noyau Debian reste le choix recommande.

## Profils

| Profil | Usage | Actions principales |
| --- | --- | --- |
| Base prudente | Serveur Debian generaliste | sysctl mesure, limites `nofile`, audit SSH et pare-feu |
| Docker | Hote multi-conteneurs | conserve les ports Docker et evite les limites memoire arbitraires |
| Web | Nginx, Apache, PHP-FPM | backlog raisonnable et ports web proposes explicitement |
| Node.js / Python | PM2, Gunicorn, services applicatifs | limites systeme sans modifier les environnements applicatifs |
| Pterodactyl / Wings | Noeud de jeux et allocations | detection des ports, aucune allocation ouverte automatiquement |
| KeyHelp | Serveur administre par KeyHelp | ne remplace pas les regles gerees par KeyHelp |

## Installation et execution

Sur un serveur Debian 13, executer cette commande en root ou avec un compte sudo :

```bash
curl -fL "https://raw.githubusercontent.com/Axxel-L/linux-optimizer-professional-server/main/linux-optimizer.sh" -o linux-optimizer.sh && chmod +x linux-optimizer.sh && sudo ./linux-optimizer.sh
```

Lien direct : [telecharger linux-optimizer.sh](https://raw.githubusercontent.com/Axxel-L/linux-optimizer-professional-server/main/linux-optimizer.sh)

Le script commence par un audit. Il demande ensuite le profil et une confirmation avant les actions sensibles. Pour produire uniquement un rapport sans modification :

```bash
sudo ./linux-optimizer.sh --audit
```

## Changements sensibles

Les choix suivants demandent une confirmation explicite :

- reglages noyau via un fichier dedie dans `/etc/linux-optimizer/` ;
- durcissement SSH dans `/etc/ssh/sshd_config.d/99-linux-optimizer.conf` ;
- ajout de regles UFW pour SSH, HTTP et HTTPS ;
- creation d'une swap de 1 Gio uniquement si aucune swap n'est activee.

Le pare-feu existant n'est pas purge. Les ports Docker, Pterodactyl, KeyHelp, bases de donnees et services internes doivent etre valides manuellement avant exposition publique.

## Sauvegardes et rollback

Les fichiers modifies sont sauvegardes avec un suffixe date dans leur emplacement d'origine. Les configurations generees sont regroupees dans :

```text
/etc/linux-optimizer/
/var/log/linux-optimizer/
```

Avant une intervention distante, conserver une session SSH ouverte et verifier la configuration avec :

```bash
sudo sshd -t
sudo sysctl --load=/etc/linux-optimizer/sysctl-base.conf
sudo ufw status verbose
```

Pour annuler une configuration, restaurer la sauvegarde datee correspondante, supprimer le fichier de configuration genere, puis recharger le service concerne apres validation.

## Prerequis

- Debian 13 recommande ; les autres distributions sont conservees comme scripts historiques et ne sont pas executees automatiquement par le nouveau lanceur.
- Acces root ou sudo.
- Bash, `systemctl`, `ss`, `sysctl` et `awk`.
- Une console ou une session SSH de secours pour les changements reseau et SSH.

## Validation locale

```bash
bash -n linux-optimizer.sh scripts/*.sh
```

Sur Debian 13 de test, executer d'abord `sudo ./linux-optimizer.sh --audit`, puis verifier les ports publies Docker, les allocations Pterodactyl et l'etat de KeyHelp avant d'appliquer un profil.

## Limites connues

- Le script ne repare pas les conteneurs `unhealthy`, les applications ou les bases de donnees.
- Il ne gere pas les stacks Docker, les allocations Pterodactyl ni les regles metier de KeyHelp.
- Il ne modifie pas automatiquement `/etc/resolv.conf` ni le fuseau horaire par geolocalisation IP.
- Les performances dependent du fournisseur, du noyau, du stockage, du reseau et de la charge reelle.

## Licence

Distribue sous licence [MIT](LICENSE).
