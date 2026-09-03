# AxelL - Linux Optimmisateur

[![Debian 13](https://img.shields.io/badge/Debian-13%20Trixie-A81D33?logo=debian&logoColor=white)](https://www.debian.org/releases/trixie/)
[![Shell](https://img.shields.io/badge/Shell-Bash-121011?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-2ea44f.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.2.0-1677ff.svg)](linux-optimizer.sh)

Outil d'audit et d'optimisation prudente pour serveurs Linux professionnels. Le projet cible en priorite **Debian 13 (Trixie)** sur des machines qui hebergent Docker, sites web, applications Node.js/Python, Pterodactyl/Wings ou KeyHelp.

> L'objectif est la fiabilite et la lisibilite des changements, pas la promesse de gains universels. Mesurez votre serveur avant et apres chaque modification importante.

## Points forts

- Audit initial en lecture seule avec OS, noyau, RAM, swap, BBR, services et ports en ecoute.
- Tableau de bord terminal redessine en direct : liste des etapes avec etat (en attente / en cours / fait / ignore / echec), pourcentage global, barre de progression et temps ecoule. Le terminal est efface au lancement. Ni spinner, ni estimation du temps restant.
- Journal horodate et rapport final dans `/var/log/linux-optimizer/`, ecrits sans code ANSI (lisibles dans un fichier ou un pipe).
- Configurations idempotentes avec sauvegardes datees.
- Configuration DNS Cloudflare (1.1.1.1) adaptee au gestionnaire reseau, toujours soumise a confirmation explicite.
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
tmp=$(mktemp -d) && wget -qO "$tmp/linux-optimizer.tar.gz" "https://github.com/Axxel-L/linux-optimizer-professional-server/archive/refs/heads/main.tar.gz" && tar -xzf "$tmp/linux-optimizer.tar.gz" -C "$tmp" && cd "$tmp/linux-optimizer-professional-server-main" && chmod +x linux-optimizer.sh scripts/*.sh && sudo ./linux-optimizer.sh
```

Archive du projet : [telecharger la derniere version](https://github.com/Axxel-L/linux-optimizer-professional-server/archive/refs/heads/main.tar.gz)

Le script commence par un audit puis propose deux modes :

- **Optimisation complete automatique** : met a jour Debian et son noyau, installe les outils necessaires, puis applique le socle et les reglages professionnels sans question intermediaire.
- **Choisir les roles** : selectionne Docker, Web, Node.js/Python, Pterodactyl ou KeyHelp ; le profil combine est ensuite applique en une seule passe.

Arguments :

```bash
sudo ./linux-optimizer.sh --audit   # rapport seul, aucune modification
sudo ./linux-optimizer.sh --full    # optimisation complete automatique
sudo ./linux-optimizer.sh --help
```

## Les 8 etapes du profil

1. Mise a jour du systeme et du noyau (APT + `linux-image-amd64` si disponible)
2. Installation des outils du profil
3. Reglages noyau et reseau (sysctl)
4. Limites de fichiers pour les services (`nofile`)
5. Validation et durcissement SSH
6. Pare-feu et ports
7. Verification de la swap
8. DNS Cloudflare (1.1.1.1)

Une etape se termine par l'un de trois etats : **fait**, **ignore** (decline ou non applicable, ex. pas d'UFW) ou **echec**. Un echec interrompt le profil et indique le chemin du journal.

### Reglages noyau et reseau

Regles prudentes, ecrites uniquement si le noyau expose la cle puis validees par `sysctl --load` (fichier supprime en cas d'echec) :

- socle : `fs.file-max`, `somaxconn`, `netdev_max_backlog`, `tcp_syncookies`, keepalive TCP, `rp_filter`, `vm.swappiness`, `vm.vfs_cache_pressure` ;
- connexions soutenues : `tcp_max_syn_backlog`, `tcp_fin_timeout`, `tcp_tw_reuse`, `tcp_mtu_probing`, `tcp_rmem`/`tcp_wmem` bornes, `ip_local_port_range` (etendu uniquement s'il est encore a la valeur par defaut) ;
- BBR + `fq` si le noyau les expose ;
- par role : inotify (Docker), `somaxconn` 8192 (Web), forwarding IPv4/IPv6 (Pterodactyl).

Un echantillon documentaire est fourni dans [files/sysctl.conf](files/sysctl.conf).

## Changements sensibles

En mode selection des roles, les choix suivants demandent une confirmation explicite :

- reglages noyau via un fichier dedie dans `/etc/linux-optimizer/` ;
- durcissement SSH dans `/etc/ssh/sshd_config.d/99-linux-optimizer.conf` ;
- ajout de regles UFW pour SSH, HTTP et HTTPS ;
- creation d'une swap de 1 Gio uniquement si aucune swap n'est activee ;
- **DNS Cloudflare** : confirmation demandee systematiquement, y compris en `--full`.

En mode `--full`, les autres etapes sont appliquees automatiquement. Le pare-feu existant n'est pas purge et aucune regle Docker/Pterodactyl, base de donnees ou service interne n'est ouverte automatiquement. Si un noyau plus recent que le noyau en cours est installe, un simple message recommande un redemarrage en fin de profil (aucune question).

## DNS Cloudflare

L'etape 8 bascule la resolution DNS vers `1.1.1.1` et `1.0.0.1` (Cloudflare), plus les adresses IPv6 `2606:4700:4700::1111` et `2606:4700:4700::1001` quand IPv6 est actif. Le gestionnaire reseau est detecte automatiquement :

| Gestionnaire | Fichier ecrit |
| --- | --- |
| systemd-resolved actif | `/etc/systemd/resolved.conf.d/99-linux-optimizer-dns.conf` + restart du service |
| netplan (fichiers YAML) | `/etc/netplan/99-linux-optimizer-dns.yaml` + `netplan apply` |
| openresolv | `/etc/resolvconf/resolv.conf.d/head` + `resolvconf -u` |
| resolv.conf statique | reecriture directe, lignes `search`/`domain`/`options` preservees |

Chaque fichier est sauvegarde (`.bak` date) avant modification, et la resolution est verifiee apres application (`getent ahosts one.one.one.one`).

Limites connues :

- glibc ne lit que les 3 premieres entrees de `resolv.conf` : en mode IPv6, seule la premiere adresse IPv6 est posee ;
- avec systemd-resolved, des DNS fournis par DHCP sur une interface particuliere peuvent primer sur la valeur globale ; pour les forcer, definir les DNS dans la configuration de l'interface (netplan, `.network`) ;
- netplan : le drop-in ne cible que les interfaces physiques declarees dans `/etc/netplan/` ;
- rollback : restaurer la sauvegarde datee (ou supprimer le drop-in) puis redemarrer le service concerné.

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

## Structure du projet

- `linux-optimizer.sh` : lanceur. Audit, menus, tableau de bord terminal, journalisation. Il source le moteur apres le choix du profil.
- `scripts/debian-optimizer.sh` : moteur du profil Debian (etapes 1-8). Sourcable par le lanceur, et executable seul pour le debogage :
  ```bash
  sudo PROFILE_MODE=web AUTO_APPLY=1 ./scripts/debian-optimizer.sh
  ```
- `scripts/ubuntu-optimizer.sh`, `fedora-optimizer.sh`, `centos-optimizer.sh` : scripts historiques conserves tels quels, non executes par le lanceur.
- `files/` : echantillons documentaires (sysctl, SSH, limites).

Convention des codes de retour des etapes (partagee entre le lanceur et le moteur) : `0` succes, `1` erreur (abandon du profil), `2` etape ignoree/declinee.

Variables d'environnement : `NO_COLOR=1` desactive les couleurs ; `PROFILE_MODE` et `AUTO_APPLY` pilotent le moteur quand il est lance seul.

## Prerequis

- Debian 13 recommande ; les autres distributions sont conservees comme scripts historiques et ne sont pas executees automatiquement par le nouveau lanceur.
- Acces root ou sudo.
- Bash, `systemctl`, `ss`, `sysctl` et `awk`.
- Une console ou une session SSH de secours pour les changements reseau et SSH.
- L'affichage en tableau de bord necessite un terminal (TTY). En sortie redirigee ou en CI, le script passe en mode texte simple sans code ANSI.

## Validation locale

```bash
bash -n linux-optimizer.sh scripts/debian-optimizer.sh
```

Sur Debian 13 de test, executer d'abord `sudo ./linux-optimizer.sh --audit`, puis verifier les ports publies Docker, les allocations Pterodactyl et l'etat de KeyHelp avant d'appliquer un profil.

## Limites connues

- Le script ne repare pas les conteneurs `unhealthy`, les applications ou les bases de donnees.
- Il ne gere pas les stacks Docker, les allocations Pterodactyl ni les regles metier de KeyHelp.
- Le fuseau horaire n'est jamais modifie.
- Les performances dependent du fournisseur, du noyau, du stockage, du reseau et de la charge reelle.

## Licence

Distribue sous licence [MIT](LICENSE).
