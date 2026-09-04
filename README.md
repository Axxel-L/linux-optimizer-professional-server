<div align="center">

# ⚡ AxelL — Linux Optimmisateur

**Audit et optimisation prudente de serveurs Linux professionnels**
*Focus Debian 13 (Trixie) — Docker · Web · Node.js/Python · Pterodactyl · KeyHelp*

<br>

[![Version](https://img.shields.io/badge/version-2.2.0-1677ff?style=for-the-badge&logo=github&logoColor=white)](linux-optimizer.sh)
[![Debian 13](https://img.shields.io/badge/Debian-13%20Trixie-A81D33?style=for-the-badge&logo=debian&logoColor=white)](https://www.debian.org/releases/trixie/)
[![Bash](https://img.shields.io/badge/Shell-Bash%205-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Licence](https://img.shields.io/badge/Licence-MIT-2ea44f?style=for-the-badge)](LICENSE)
[![Fork](https://img.shields.io/badge/Fork%20de-Linux--Optimizer-555555?style=for-the-badge&logo=github)](https://github.com/hawshemi/Linux-Optimizer)

**Un outil, un écran, une trace : chaque optimisation est visible, expliquée et réversible.**

</div>

---

## 📌 À propos

`linux-optimizer.sh` audite votre serveur **en lecture seule**, puis applique un profil d'optimisation **prudent et idempotent** : mise à jour système, réglages noyau et TCP, limites de fichiers, durcissement SSH, pare-feu, swap et DNS Cloudflare — le tout piloté depuis un **tableau de bord terminal en direct**.

> **La philosophie du projet : la fiabilité et la lisibilité des changements, pas la promesse de gains universels.** Chaque réglage est validé avant application, sauvegardé avant modification, et documenté dans un journal horodaté.

### 🍴 Origine du projet (fork)

Ce dépôt est un **fork de [Linux-Optimizer](https://github.com/hawshemi/Linux-Optimizer)** (Hawshemi, 2023, licence MIT — voir [LICENSE](LICENSE)).

- l'historique multi-distributions (Ubuntu, Fedora, CentOS) a été **retiré** pour ne garder qu'une ligne de code maintenue et testée — **Debian** ;
- la version active (v2.2+) est une **réécriture complète orientée serveurs professionnels** : elle cible Debian 13, remplace l'ancienne sortie texte par un tableau de bord live et un journal sans ANSI, ajoute un profil « full » automatique, des profils métier combinables et une gestion DNS Cloudflare prudente.

---

## ✨ Pourquoi utiliser ces scripts ?

| | |
| --- | --- |
| 🔍 **Audit d'abord** | Rien n'est modifié avant que vous n'ayez vu l'état réel du serveur (OS, noyau, RAM/swap, BBR, services, ports). |
| 🛡️ **Prudent par conception** | Validation avant application : `sshd -t` avant tout reload SSH, `sysctl --load` avant de conserver un fichier, rollback automatique en cas d'échec. |
| 💾 **Toujours réversible** | Chaque fichier modifié est sauvegardé avec un suffixe daté sur place. |
| 🐳 **Respectueux du métier** | Profils Docker, Web, Node.js/Python, Pterodactyl/Wings, KeyHelp : pas de purge de pare-feu, pas d'ouverture de port automatique, ports Docker préservés. |
| 🌐 **DNS Cloudflare en option** | `1.1.1.1` / `1.0.0.1` (+ IPv6) appliqués selon votre gestionnaire réseau, **toujours avec confirmation explicite**. |
| 🖥️ **Interface terminal moderne** | Splash d'accueil, tableau de bord étape par étape avec états en direct et chrono fluide ; la barre reste stable pendant l'étape et avance à chaque transition. |
| 📜 **Journal professionnel** | Rapport horodaté dans `/var/log/linux-optimizer/`, sans code ANSI, avec chaque étape, ses diagnostics et les erreurs fatales. |
| ♻️ **Idempotent** | Relancez le script sans risque : les configurations déjà en place ne sont pas dupliquées. |

### 🏢 … et pourquoi sur des serveurs professionnels ?

Un serveur de production n'est pas une machine de test : une « optimisation » ratée peut couper un site, casser Docker ou verrouiller une session SSH distante.

Ce projet est pensé pour ce contexte :

- **aucun changement destructeur** : pas de purge de règles, pas de remplacement de configuration métier, pas de réinstallation de noyau tiers (XanMod n'est jamais installé automatiquement) ;
- **des garde-fous opérationnels** : session SSH de secours recommandée, rechargement SSH uniquement après validation, pare-feu jamais ouvert sur des ports internes ;
- **des changements audités et datés** : un rapport complet permet de répondre « qu'est-ce qui a changé, quand, et comment l'annuler ? » — indispensable en production ou en contexte audité ;
- **mesurez avant/après** : l'outil prépare le terrain (noyau, sysctl, limites), les gains réels dépendent de votre workload — le script ne le cache pas.

---

## 🖥️ Aperçu

### Splash d'accueil

```text
┌━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┐
│                                                            │
│                    ██   █  █  ████  █                      │
│                   █  █   █ █  █     █                      │
│                   ████    █   ███   █                      │
│                   █  █   █ █  █     █                      │
│                   █  █  █  █  ████  ████                   │
│                                                            │
│                AxelL - Linux Optimmisateur                 │
│   Audit et optimisation prudente d'un serveur Debian 13    │
│                        v2.2.0 | MIT                        │
│                                                            │
└━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┘
```

### Tableau de bord du profil (mis à jour en direct)

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  AxelL - Linux Optimmisateur   Debian 13 | v2.2.0 | MIT
  Profil : full
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [✓]  01/08  Mise a jour du systeme et du noyau
  [▶]  02/08  Installation des outils du profil
  [·]  03/08  Reglages noyau et reseau
  [·]  04/08  Limites de fichiers pour les services
  [·]  05/08  Validation et durcissement SSH
  [·]  06/08  Pare-feu et ports
  [·]  07/08  Verification de la swap
  [·]  08/08  DNS Cloudflare (1.1.1.1)

  ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  12%   00m00s
```

---

## 🚀 Démarrage rapide

Sur un serveur Debian 13, en root ou avec un compte `sudo` :

```bash
wget -qO- "https://raw.githubusercontent.com/Axxel-L/linux-optimizer-professional-server/main/install.sh" | sudo bash
```

Ou directement depuis une archive : [télécharger la dernière version](https://github.com/Axxel-L/linux-optimizer-professional-server/archive/refs/heads/main.tar.gz).

### Modes de lancement

```bash
sudo ./linux-optimizer.sh                # interactif : audit + choix du mode
sudo ./linux-optimizer.sh --full         # optimisation complète automatique
sudo ./linux-optimizer.sh --audit        # rapport seul, aucune modification
sudo ./linux-optimizer.sh --help
```

### Rapports et erreurs

Chaque lancement crée un rapport texte dans `/var/log/linux-optimizer/`. Les débuts et fins d'étapes, les avertissements, les diagnostics des commandes et les erreurs fatales y sont écrits avec leur date et leur heure. Le chemin exact du rapport est affiché à la fin d'une exécution réussie, après un audit, ou lors d'un échec contrôlé.

Dans un conteneur LXC, l'étape des réglages noyau est détectée et ignorée automatiquement : le noyau est partagé avec l'hôte et ses paramètres doivent être modifiés depuis celui-ci.

### Migration Debian

Au démarrage, le lanceur compare la version installée avec la stable Debian officielle. Si la release suivante est confirmée, il affiche la cible avant l'audit et demande s'il faut lancer la migration, continuer sans migration ou quitter. Une détection incertaine arrête le lancement par sécurité.

La migration est réalisée par [scripts/debian-release-upgrade.sh](scripts/debian-release-upgrade.sh) et n'est jamais automatique. Elle exige un terminal interactif, refuse les conteneurs LXC et ne permet qu'un passage vers la release immédiatement suivante. Chaque phase sensible est confirmée : sauvegarde, dépôts, mise à jour APT, simulation, installation et nettoyage.

Le script sauvegarde `/etc/apt`, la liste des paquets, les services activés et les fichiers de configuration importants dans `/var/backups/linux-optimizer/`. Les dépôts tiers sont signalés puis désactivés uniquement après confirmation. Une migration majeure ne dispose pas d'un rollback complet garanti : le redémarrage n'est jamais exécuté automatiquement et doit être fait manuellement après vérification.

Pour lancer la procédure directement :

```bash
sudo ./scripts/debian-release-upgrade.sh
```

Le moteur peut aussi être lancé directement pour le débogage :

```bash
sudo PROFILE_MODE=web AUTO_APPLY=1 ./scripts/debian-optimizer.sh
```

Ce mode produit également son propre rapport et affiche son emplacement. Un arrêt impossible à intercepter par Bash, comme `SIGKILL`, une coupure électrique ou un kernel panic, ne peut pas écrire de ligne finale.

En interactif, deux modes sont proposés :

1. **Optimisation complète automatique** — met à jour Debian et son noyau, installe les outils et applique le socle ; les changements sensibles comme les réglages noyau, SSH et DNS restent expliqués et soumis à confirmation ;
2. **Choisir les rôles** — sélectionnez Docker, Web, Node.js/Python, Pterodactyl ou KeyHelp ; le profil combiné est appliqué en une seule passe.

---

## 🧩 Profils disponibles

| Profil | Usage | Actions principales |
| --- | --- | --- |
| **Base prudente** | Serveur Debian généraliste | sysctl mesuré, limites `nofile`, audit SSH et pare-feu |
| **Docker** | Hôte multi-conteneurs | conserve les ports Docker, évite les limites mémoire arbitraires |
| **Web** | Nginx, Apache, PHP-FPM | backlog raisonnable, ports web proposés explicitement |
| **Node.js / Python** | PM2, Gunicorn, services applicatifs | limites système sans toucher aux environnements applicatifs |
| **Pterodactyl / Wings** | Nœud de jeux et allocations | détection des ports, aucune allocation ouverte automatiquement |
| **KeyHelp** | Serveur administré par KeyHelp | ne remplace pas les règles gérées par KeyHelp |

---

## ⚙️ Les 8 étapes du profil

<details>
<summary><b>1. Mise à jour du système et du noyau</b></summary>

Mise à jour des index APT, upgrade des paquets, puis `linux-image-amd64` + `linux-headers-amd64` si un noyau plus récent est disponible. Si un noyau plus récent que le noyau en cours est installé, un message recommande un redémarrage en fin de profil.
</details>

<details>
<summary><b>2. Installation des outils du profil</b></summary>

Outils de base (`curl`, `jq`, `htop`, `rsync`…) puis outils selon les rôles choisis (python3/nodejs, nginx, uidmap…). En mode `full`, seuls les outils de base sont installés : les services applicatifs ne sont jamais installés automatiquement.
</details>

<details>
<summary><b>3. Réglages noyau et réseau</b></summary>

Écrit dans `/etc/linux-optimizer/sysctl-<profil>.conf`, uniquement les clés exposées par le noyau, puis validation par `sysctl --load` (le fichier est supprimé en cas d'échec) :

- socle : `fs.file-max`, `somaxconn`, `netdev_max_backlog`, `tcp_syncookies`, keepalive TCP, `rp_filter`, `vm.swappiness`, `vm.vfs_cache_pressure` ;
- connexions soutenues : `tcp_max_syn_backlog`, `tcp_fin_timeout`, `tcp_tw_reuse`, `tcp_mtu_probing`, `tcp_rmem`/`tcp_wmem` bornés, `ip_local_port_range` (étendu seulement s'il est encore à la valeur par défaut) ;
- BBR + `fq` si le noyau les expose ;
- par rôle : inotify (Docker), `somaxconn` 8192 (Web), forwarding IPv4/IPv6 (Pterodactyl).

Échantillon documentaire : [files/sysctl.conf](files/sysctl.conf).
</details>

<details>
<summary><b>4. Limites de fichiers pour les services</b></summary>

Configure la limite `nofile` (soft et hard, minimum 65536) dans `/etc/linux-optimizer/limits.conf`, sans modifier `/etc/profile`.
</details>

<details>
<summary><b>5. Validation et durcissement SSH</b></summary>

L'étape pose des questions avant de modifier `/etc/ssh/sshd_config.d/99-linux-optimizer.conf` : connexion root (`PermitRootLogin`), mots de passe (`PasswordAuthentication`), clés (`PubkeyAuthentication`), tunnels (`AllowTcpForwarding`/`GatewayPorts`/`PermitTunnel`) et X11 (`X11Forwarding`). Une réponse vide conserve la valeur actuelle. Le script explique chaque impact, notamment le risque de perdre l'accès distant en désactivant root ou les mots de passe. Il valide avec `sshd -t` avant tout rechargement et restaure l'ancienne configuration si la validation ou le reload échoue.
</details>

<details>
<summary><b>6. Pare-feu et ports</b></summary>

Liste les ports en écoute (et les ports Docker publiés), puis propose — uniquement sur confirmation — d'ajouter le port SSH détecté + 80/443 à UFW. `firewalld` actif : aucune modification. UFW absent : le pare-feu n'est pas installé automatiquement.
</details>

<details>
<summary><b>7. Vérification de la swap</b></summary>

Si aucune swap n'est active, propose de créer `/swapfile` de 1 Gio (avec entrée `/etc/fstab`). Jamais de taille imposée si une swap existe déjà.
</details>

<details>
<summary><b>8. DNS Cloudflare (1.1.1.1)</b></summary>

Voir la section dédiée ci-dessous.
</details>

**États possibles d'une étape :** `fait` · `ignoré` (décliné ou non applicable) · `échec` (le profil s'interrompt et indique le chemin du journal).

---

## 🌐 Étape 8 : DNS Cloudflare

L'étape 8 bascule la résolution DNS vers **`1.1.1.1`** et **`1.0.0.1`** (Cloudflare — rapide et sécurisé), plus `2606:4700:4700::1111` / `2606:4700:4700::1001` (IPv6) quand IPv6 est actif.

Le gestionnaire réseau est **détecté automatiquement** :

| Gestionnaire détecté | Fichier écrit |
| --- | --- |
| `systemd-resolved` actif | `/etc/systemd/resolved.conf.d/99-linux-optimizer-dns.conf` + restart du service |
| `netplan` (fichiers YAML présents) | `/etc/netplan/99-linux-optimizer-dns.yaml` + `netplan apply` |
| `openresolv` | `/etc/resolvconf/resolv.conf.d/head` + `resolvconf -u` |
| `resolv.conf` statique | réécriture directe en préservant `search`/`domain`/`options` |

Garde-fous :

- **confirmation demandée systématiquement, y compris en `--full`** ;
- sauvegarde datée (`.bak`) de chaque fichier avant modification ;
- vérification post-application : `getent ahosts one.one.one.one` ;
- limites connues : glibc ne lit que 3 entrées de `resolv.conf` (1 seule IPv6 posée en mode statique) ; avec systemd-resolved, des DNS fournis par DHCP sur une interface peuvent primer — dans ce cas, définissez les DNS au niveau de l'interface (netplan, `.network`).

---

## 💾 Sauvegardes et rollback

Les fichiers modifiés sont sauvegardés **sur place** avec un suffixe daté : `fichier.linux-optimizer.<horodatage>.bak`. Les configurations générées sont regroupées dans :

```text
/etc/linux-optimizer/          # configurations actives (sysctl, limits, ssh)
/var/log/linux-optimizer/      # rapports horodatés
```

Avant une intervention distante : gardez une session SSH ouverte et vérifiez :

```bash
sudo sshd -t
sudo sysctl --load=/etc/linux-optimizer/sysctl-base.conf
sudo ufw status verbose
```

**Annuler une configuration** : restaurer la sauvegarde datée, supprimer le fichier généré, puis recharger le service concerné après validation.

---

## 📁 Structure du projet

```text
.
├── linux-optimizer.sh              # Lanceur : audit, menus, tableau de bord, journal
├── scripts/
│   └── debian-optimizer.sh         # Moteur du profil Debian (8 étapes) — sourçable & exécutable
├── files/                          # Échantillons documentaires (sysctl, sshd_config, profile)
├── .github/ISSUE_TEMPLATE/         # Modèles de signalement
└── LICENSE                         # MIT (copyright upstream 2023 Hawshemi)
```

**Architecture** : le lanceur source le moteur après le choix du profil (`PROFILE_MODE` / `AUTO_APPLY`), puis exécute ses étapes une à une. Convention des codes de retour partagée : `0` = succès · `1` = erreur (abandon) · `2` = étape ignorée/déclinée.

Exécution directe du moteur (débogage) :

```bash
sudo PROFILE_MODE=web AUTO_APPLY=1 ./scripts/debian-optimizer.sh
```

---

## ✅ Prérequis

- **Debian 13** — unique distribution supportée par le lanceur ;
- accès **root** ou `sudo` ;
- `bash`, `systemctl`, `ss`, `sysctl`, `awk` ;
- une **console ou session SSH de secours** pour les changements réseau/SSH ;
- le tableau de bord nécessite un **terminal (TTY)** ; en sortie redirigée ou CI, le script bascule automatiquement en mode texte simple sans code ANSI.

---

## 🧪 Validation

```bash
bash -n linux-optimizer.sh scripts/*.sh
```

Sur un Debian 13 de test : d'abord `sudo ./linux-optimizer.sh --audit`, vérifiez les ports Docker publiés, les allocations Pterodactyl et l'état KeyHelp, **puis** appliquez un profil.

Variables d'environnement : `NO_COLOR=1` désactive les couleurs.

---

## ⚠️ Limites connues

- Le script ne répare pas les conteneurs `unhealthy`, les applications ni les bases de données ;
- il ne gère pas les stacks Docker, les allocations Pterodactyl ni les règles métier KeyHelp ;
- le fuseau horaire n'est jamais modifié ;
- les performances réelles dépendent du fournisseur, du noyau, du stockage, du réseau et de la charge — mesurez avant/après.

---

## 📜 Changelog

**v2.2.0**
- Tableau de bord terminal en direct (états, %, chrono) + splash d'accueil ;
- nouvelle étape **DNS Cloudflare (1.1.1.1)** avec détection du gestionnaire réseau et confirmation systématique ;
- réglages TCP/noyau étoffés et prudents ;
- journal `/var/log/linux-optimizer/` sans code ANSI ;
- moteur Debian sourçable, profils combinables, moteur exécutable seul pour le débogage ;
- note « redémarrage recommandé » si un noyau plus récent est installé.

**v2.1.0 et antérieures** — refonte progressive du fork vers une ligne « serveur professionnel » Debian (profils, sauvegardes, audit).

---

## 🤝 Contribuer

Issues et pull requests bienvenues — merci de passer `bash -n` et de tester sur une VM Debian 13 avant de proposer une modification. Consultez les [modèles de signalement](.github/ISSUE_TEMPLATE/).

## 🙏 Crédits

Ce projet est un **fork de [Linux-Optimizer](https://github.com/hawshemi/Linux-Optimizer)** par **Hawshemi** (MIT, 2023), dont s'inspirent l'architecture et certains réglages. Le projet se concentre désormais **exclusivement sur Debian 13**.

## 📄 Licence

Distribué sous licence [MIT](LICENSE). Copyright upstream conservé (© 2023 Hawshemi).
