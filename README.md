# Évaluation expérimentale de la compression dans Spark

Projet InfraCloud — sujet complet : [docs/sujet.pdf](docs/sujet.pdf).

## 1. Objectif

Compresser les données réduit les octets lus, écrits et envoyés sur le réseau, mais coûte du CPU.
Le projet consiste à **mesurer quand ce compromis est gagnant ou perdant** dans Spark, selon :

| Ce qu'on fait varier | Valeurs |
|---|---|
| Codec | aucun (baseline), Snappy, LZ4, Gzip, Zstd |
| Niveau de compression | C0 aucun · C1 stockage (HDFS) · C2 shuffle (réseau) · C3 les deux |
| Profil d'application | I/O-bound · CPU-bound · mixte |
| Taille des données | 1, 5, 10, 20 Go |

On mesure le temps total, le temps de shuffle, le CPU, les octets disque et réseau, et la taille compressée.
On produit ensuite les 7 courbes demandées et on répond aux 7 questions du sujet **avec des preuves expérimentales**.

## 2. Organisation de l'équipe

### Principe

```
 Socle commun (infra, applis, données, runner)  ──►  Campagnes en parallèle  ──►  Analyse commune
        une seule version, figée (tag v1.0)           1 personne = 1 application     CSV fusionnés
```

1. **Un seul socle pour tout le monde.** Même Terraform, même Ansible, mêmes VMs, mêmes versions, même config Spark de base.
   Seuls les **paramètres de compression** changent d'un run à l'autre.
2. **Chacun déploie ce socle sur son propre compte GCP** (crédits d'essai) et y fait tourner **son** bloc d'expériences.
3. **On découpe les campagnes par application, pas par section du sujet.**
   Les sections 5.1, 5.2 et 5.3 sont des tranches d'une même grille *codec stockage × codec shuffle* : C1 = runs de 5.1, C2 = runs de 5.2.
   Si on les répartissait entre plusieurs personnes, il faudrait comparer des runs faits sur des clusters différents.
   En découpant par appli, **toutes les comparaisons d'une même appli sont faites sur le même cluster**.

### Phase 1 — Socle commun (jusqu'au ~7 décembre)

Pas besoin de tout diviser : l'infra initiale est montée par une personne, les autres avancent en parallèle sur ce qui n'en dépend pas.

| Chantier | Qui | Dépend de |
|---|---|---|
| Infra : Terraform + Ansible + monitoring (**ce repo, fait**) | _à compléter_ | — |
| Micro-benchmark des codecs seuls (§4 du sujet : ratio, vitesse, CPU) | _à compléter_ | rien, faisable en local |
| Les 3 applications + générateur de données | _à compléter_ | rien, faisable en local |
| Runner d'expériences + format CSV des résultats | _à compléter_ | infra |

### Phase 2 — Pilote (semaine du 8 décembre)

Un seul compte GCP, petites tailles. On valide l'infra, **on prouve le profil de chaque appli** (I/O, CPU, mixte) avec les métriques,
on mesure la durée réelle des runs, puis on fige la grille d'expériences et on pose le tag **`v1.0`**.

### Phase 3 — Campagne (du 15 décembre à début janvier)

| Personne | Bloc | Contenu |
|---|---|---|
| P1 | Appli **I/O-bound** | balayage stockage, balayage shuffle, C0–C3, 4 tailles |
| P2 | Appli **CPU-bound** | idem |
| P3 | Appli **mixte** | idem |
| P4 | **Transversal** | micro-benchmark des codecs, scripts de graphes, cohérence du protocole |

Chacun lance aussi un même **benchmark de calibration** : si les clusters donnent les mêmes temps en C0, on a la preuve qu'ils sont équivalents.
Les comparaisons entre applis se font en **gain relatif** (temps / temps C0 de la même appli), ce qui neutralise les petits écarts entre clusters.

### Phase 4 — Analyse, rapport, soutenance (janvier)

Les 7 questions sont transversales : on les rédige ensemble sur le CSV fusionné.
Chacun rédige la partie de son application et doit pouvoir la défendre à l'oral.

### Dépendances à respecter

- Le **socle** bloque tout le reste. Une fois `v1.0` posé, **on n'y touche plus** pendant la campagne.
- La **caractérisation des applis** est bloquante : si l'appli « I/O-bound » se révèle CPU-bound, toute sa campagne est à refaire. On la valide pendant le pilote.
- Dans chaque bloc, on fait d'abord les balayages de codecs, **puis** on choisit les codecs de C3.
- **Les données sont les mêmes pour tout le monde** : même générateur, même graine, régénérées sur chaque cluster.

## 3. Infrastructure

```
                     ┌──────────────── cbench-master (n2-standard-2) ────────────────┐
  vous ──SSH──►      │ HDFS NameNode · YARN ResourceManager · driver Spark            │
  (tunnel pour       │ Spark History Server · Prometheus · Grafana · outils de mesure │
   les UIs web)      └──────────────────────────────┬─────────────────────────────────┘
                                                    │ réseau privé 10.10.0.0/24, une seule zone
               ┌────────────────────────────────────┼────────────────────────────────────┐
   cbench-worker-1 (n2-standard-2)       cbench-worker-2                        cbench-worker-3
   DataNode · NodeManager                     idem                                   idem
   1 exécuteur Spark (2 cœurs, 4 Go)
   disque /data 200 Go : HDFS + shuffle
   node_exporter (sur tous les nœuds)
```

4 VMs × 2 vCPU = **8 vCPU**, soit le plafond de l'essai gratuit GCP.

### Choix faits pour des mesures fiables

| Choix | Pourquoi |
|---|---|
| VMs **n2** (vCPU dédiés) + `min_cpu_platform = Intel Ice Lake` | Pas de crédits CPU comme sur e2/t3/B-series ; **même génération de CPU** sur les 4 clusters de l'équipe |
| VMs standard, **jamais Spot** | Une VM Spot peut être arrêtée en plein run |
| **Une seule zone**, réseau privé dédié | Latence réseau homogène entre les nœuds |
| **Disque /data séparé** en `pd-balanced` | HDFS et shuffle isolés du disque système ; performances prévisibles (pas de HDD `pd-standard`) |
| **Versions figées** + empreintes SHA vérifiées ; image OS figée au tag `v1.0` | Tout le monde exécute exactement le même logiciel |
| **Ressources Spark fixes** : 1 exécuteur/worker, pas d'allocation dynamique, pas de spéculation | Le même nombre de cœurs et la même mémoire à chaque run |
| **AQE désactivé**, nombre de partitions de shuffle fixe | Sinon Spark adapte le plan d'exécution à la taille *compressée* du shuffle, et on ne compare plus la même chose |
| **Baseline C0 explicite** : toute compression coupée dans `spark-defaults.conf` | Spark compresse le shuffle **par défaut** ; le runner active la compression run par run avec `--conf` |
| **Tâches de fond coupées** : mises à jour apt/snap, logrotate, fstrim, man-db ; swap et THP désactivés | Pas de pic CPU ou disque parasite au milieu d'une mesure |
| `cluster-drop-caches` | Vide le page cache de tous les nœuds avant chaque run, pour que tous les runs partent à froid |
| `cluster-fingerprint` | Empreinte JSON du cluster (CPU, mémoire, versions…) jointe aux résultats, pour prouver que deux clusters sont identiques |
| `cluster-smoke-test` | Vérifie HDFS, YARN, les bibliothèques natives et **chaque codec**, au stockage comme au shuffle |
| Prometheus + node_exporter toutes les **2 s** | CPU, disque et réseau par nœud et par périphérique, interrogeables sur l'intervalle exact de chaque run |

### Versions

| Composant | Version |
|---|---|
| Ubuntu | 24.04 LTS |
| Java | OpenJDK 17 |
| Hadoop (HDFS + YARN) | 3.5.0 |
| Spark | 4.1.4 (sur YARN) |
| Prometheus / node_exporter | 3.16.0 / 1.13.1 |
| Terraform / ansible-core (toolbox) | 1.17.2 / 2.22.0 |

### Limites connues à garder en tête pour le rapport

- **Gzip n'existe pas pour le shuffle dans Spark** : les codecs de shuffle sont `lz4`, `lzf`, `snappy` et `zstd`. Gzip n'est donc évalué qu'au niveau stockage.
- **Un fichier texte compressé (gzip, snappy, lz4, zstd) ne peut pas être découpé** : une seule tâche le lit en entier.
  Il faudra écrire les données en **beaucoup de fichiers** (~128 Mo chacun), ou utiliser Parquet, qui reste découpable avec tous les codecs. À trancher avec le prof.
- L'*application master* YARN partage un worker avec un exécuteur : c'est un léger déséquilibre, mais il est identique pour tous les runs.

## 4. Démarrage (pour chaque membre)

**Prérequis** : Docker Desktop, [gcloud CLI](https://cloud.google.com/sdk/docs/install), un compte GCP.
Terraform et Ansible tournent **dans un conteneur** (`toolbox/`), donc tout le monde a les mêmes versions, quel que soit son OS.

> ⚠️ L'essai GCP dure **90 jours à partir de l'activation**. Ne l'activer qu'au moment où on en a besoin (pilote ou campagne).

1. **Créer un projet GCP** dans la console (rattaché au compte de facturation de l'essai), puis noter son ID.
2. **Identifiants pour Terraform** :
   ```
   gcloud auth application-default login
   gcloud auth application-default set-quota-project <PROJECT_ID>
   mkdir .secrets
   ```
   Puis copier le fichier d'identifiants dans `.secrets/gcp-adc.json` :
   - Windows (PowerShell) : `Copy-Item "$env:APPDATA\gcloud\application_default_credentials.json" .secrets\gcp-adc.json`
   - Linux/macOS : `cp ~/.config/gcloud/application_default_credentials.json .secrets/gcp-adc.json`
3. **Variables personnelles** : copier `infra/terraform/terraform.tfvars.example` en `terraform.tfvars` et remplir les 3 lignes (ID du projet, prénom, IP publique).
4. **Déployer** :
   ```
   docker compose run --rm toolbox      # ouvre un shell dans la toolbox
   make init                            # une seule fois
   make cluster                         # VMs + installation + smoke test (~15 min)
   ```
5. **Interfaces web** (dans un autre terminal) : `docker compose run --rm --service-ports toolbox make tunnel`
   → HDFS http://localhost:9870 · YARN http://localhost:8088 · Spark http://localhost:18080 · Prometheus http://localhost:9090 · Grafana http://localhost:3000 (admin/admin)
6. **À la fin de chaque session : `make down`.** On paie à l'heure, environ **0,55 $/h** pour le cluster, soit ~13 $ par jour s'il reste allumé.
   Les disques sont supprimés aussi : récupérer ses résultats avant.

| Commande | Effet |
|---|---|
| `make up` / `make down` | Crée / détruit les VMs, le réseau et les disques |
| `make provision` | (Ré)installe et (re)configure tout ; peut être relancé sans risque |
| `make smoke` | Vérifie que le cluster est prêt pour les mesures |
| `make ssh` | Shell sur le master |
| `make fingerprint` | Empreinte JSON du cluster |
| `make help` | Toutes les commandes |

Sur le master : `cluster-smoke-test`, `cluster-drop-caches`, `cluster-fingerprint`. Pour travailler avec Hadoop/Spark : `sudo -iu hadoop`.

## 5. Structure du repo

```
docs/                 Sujet du projet
infra/terraform/      VMs, réseau, pare-feu, disques (GCP)
infra/ansible/        Installation : OS, Java, Hadoop, Spark, monitoring, outils de mesure
  group_vars/all.yml  ← configuration commune du cluster (versions, mémoire, HDFS…)
  roles/spark/templates/spark-defaults.conf.j2  ← config Spark de base = C0
toolbox/              Conteneur Terraform + Ansible commun
Makefile              Commandes du projet (à lancer dans la toolbox)
```

À venir : `apps/` (les 3 applications), `data/` (générateur), `runner/` (lancement des grilles d'expériences),
`experiments/` (un plan YAML par personne), `results/<prénom>/` (CSV bruts), `microbench/`, `analysis/` (graphes).

## 6. Règles Git

- On ne travaille jamais directement sur `main` : une branche par sujet (`infra/…`, `apps/…`, `runner/…`), puis une pull request relue par au moins une autre personne.
- Toute modification de la **partie commune** (infra, config Spark, applis, runner) passe par une PR, car elle change les conditions de mesure.
- On ne commite **jamais** `.secrets/`, `terraform.tfvars` ou `*.tfstate` (déjà dans `.gitignore`).
