# ubuntu-env

Ambiente di sviluppo "tutto incluso" basato su Docker. In un singolo container trovi già pronti i principali linguaggi e strumenti (Node, Python, Go, Rust, Ruby/Rails, Java, AWS CLI, kubectl, OpenTofu, Claude Code, client di database, ecc.) senza dover installare nulla sulla tua macchina.

L'immagine viene ricostruita ogni notte e pubblicata su GitHub Container Registry come `ghcr.io/manprint/ubuntu-env:latest`, così hai sempre versioni aggiornate dei tool.

---

## Prerequisiti

L'unica cosa che ti serve sul tuo computer è **Docker**. Niente Node, niente Python, niente di niente: tutto vive dentro il container.

### Linux

Installa Docker Engine seguendo la guida ufficiale della tua distribuzione. Assicurati che il tuo utente sia nel gruppo `docker` così non devi usare `sudo` per ogni comando.

### Windows

1. Installa **Docker Desktop for Windows**: <https://www.docker.com/products/docker-desktop/>
2. Durante l'installazione lascia attiva l'opzione "Use WSL 2 instead of Hyper-V" (consigliata). Se non hai WSL 2, l'installer ti guiderà ad attivarlo.
3. Dopo l'installazione apri **Docker Desktop** almeno una volta e attendi che lo stato in basso a sinistra diventi verde ("Engine running").
4. Apri **PowerShell** o **Windows Terminal** e verifica con `docker --version`.

> Per i comandi `docker compose` di questa guida ti consigliamo di lavorare **dentro WSL 2** (es. Ubuntu da Microsoft Store). Le performance dei volumi montati sono molto migliori se il progetto vive nel filesystem di WSL (`/home/tuoutente/...`) piuttosto che in `C:\Users\...`.

### macOS

1. Installa **Docker Desktop for Mac**: <https://www.docker.com/products/docker-desktop/>
   - Su Mac Apple Silicon (M1/M2/M3/M4) scarica la versione "Apple Silicon".
   - Su Mac Intel scarica la versione "Intel chip".
2. Apri **Docker Desktop** almeno una volta e attendi che la balena nella barra dei menu smetta di animarsi.
3. Apri il **Terminale** e verifica con `docker --version`.

> Su Apple Silicon il container gira in modo nativo (l'immagine è multi-arch, esiste anche per `arm64`), quindi non c'è perdita di performance.

---

## Avvio rapido

1. Clona o copia questa cartella sul tuo computer.
2. Dal terminale, posizionati nella cartella del tuo progetto (quella che vuoi montare dentro il container).
3. Copia `compose.yml` nella cartella del progetto (oppure lavora direttamente dalla cartella che lo contiene).
4. Modifica le variabili di ambiente e mounts (maggiori dettagli nelle sezioni a seguire)
5. Avvia:

   ```bash
   docker compose up -d
   ```

6. Entra nel container:

   ```bash
   docker compose exec --user ubuntu ubuntu-env bash
   ```

Adesso sei dentro un ambiente Linux con tutti i tool già installati. La cartella in cui sei sul tuo computer è disponibile dentro il container in `/workspace`: ogni modifica che fai dentro il container ai file viene riflessa immediatamente sul tuo PC, e viceversa.

Per fermare il container:

```bash
docker compose down
```

---

## A cosa servono i volumi (la sezione `volumes:`)

I "volumi" sono ponti tra cartelle/file del tuo computer e cartelle/file dentro il container. Servono a far sì che il container possa lavorare con i tuoi file e ricordare le tue impostazioni.

Nel `compose.yml` ce ne sono cinque:

### `$PWD:/workspace`
Monta la cartella corrente del tuo computer come `/workspace` dentro il container. È **dove lavori**: tutto quello che modifichi qui dentro è visibile e modificabile dal container, e viceversa. Quando esci dal container i tuoi file restano sul tuo PC.

### `/var/run/docker.sock:/var/run/docker.sock`
Permette al container di parlare con il Docker del tuo computer. Serve solo se dentro il container vuoi usare comandi `docker` (per esempio per costruire altre immagini). Se non ti serve puoi tranquillamente rimuovere questa riga.

### `/home/user/.claude:/home/ubuntu/.claude`
Cartella di configurazione di **Claude Code**. Montando la tua configurazione dall'esterno, mantieni la cronologia, le sessioni e le impostazioni di Claude tra un riavvio e l'altro del container.

### `/home/user/.claude.json:/home/ubuntu/.claude.json`
File con le credenziali/impostazioni globali di Claude Code. Anche questo va tenuto fuori dal container per non perderlo a ogni `docker compose down`.

### `/home/user/.git-credentials:/home/ubuntu/.git-credentials`
Credenziali Git memorizzate. Eviti di doverti ri-loggare a GitHub/GitLab ogni volta che entri nel container.

> **Importante per Windows e macOS:** il path `/home/user/...` è un esempio Linux. Vedi più sotto la sezione "Adattare i percorsi" per la sintassi corretta sul tuo sistema.

---

## A cosa servono le variabili (la sezione `environment:`)

Sono opzioni che personalizzano il comportamento del container al primo avvio. Puoi cambiarle direttamente nel `compose.yml`, oppure metterle in un file `.env` nella stessa cartella (vedi più sotto).

### `GRANT_PERMISSION` (default: `1000`)
Lista di **GID** (numerici, separati da virgola) del tuo PC che vengono aggiunti come gruppi supplementari all'utente `ubuntu` dentro il container. Serve a fargli leggere/scrivere i file montati senza errori di permessi.

Esempio: se sul tuo PC il tuo utente principale ha GID `1000` e il gruppo `docker` ha GID `999`, imposta `GRANT_PERMISSION=1000,999`.

> Su macOS e Windows con Docker Desktop non te ne devi quasi mai preoccupare: Docker Desktop gestisce in automatico la traduzione dei permessi. Lascia il default `1000`.

### `WORKSPACE_UMASK` (default: `002`)
Determina i permessi predefiniti dei nuovi file creati nel container. `002` significa "file e cartelle scrivibili anche dal gruppo": utile quando lavori in team o condividi cartelle.

### `GIT_USER` (default: `user`)
Nome che verrà usato dai commit Git fatti dentro al container. Mettici il tuo nome.

### `GIT_MAIL` (default: `user@dev.it`)
Email Git per i commit. Mettici la tua.

### `PROMPT_TAG` (default: `ubuntu-env`)
Etichetta colorata mostrata nel prompt della shell dentro al container. Utile se hai più container aperti e vuoi distinguerli a colpo d'occhio.

### `TERM` (default: `xterm-256color`)
Tipo di terminale. Tieni il default; cambialo solo se hai problemi di rendering di colori o caratteri speciali.

---

## Adattare i percorsi al tuo sistema

I path nei volumi `/home/user/.claude`, `/home/user/.claude.json`, `/home/user/.git-credentials` sono scritti come esempio Linux. Devi adattarli al tuo computer:

### Linux
Sostituisci `user` con il tuo nome utente. Esempio:
```yaml
- /home/mario/.claude:/home/ubuntu/.claude
```

### macOS
Su Mac la home è in `/Users/`. Esempio:
```yaml
- /Users/mario/.claude:/home/ubuntu/.claude
- /Users/mario/.claude.json:/home/ubuntu/.claude.json
- /Users/mario/.git-credentials:/home/ubuntu/.git-credentials
```

### Windows (con Docker Desktop)
Se lavori da **WSL 2** (consigliato), usa i percorsi Linux dentro WSL:
```yaml
- /home/mario/.claude:/home/ubuntu/.claude
```

Se lavori da PowerShell con i percorsi Windows, usa la sintassi con la lettera del disco:
```yaml
- C:/Users/Mario/.claude:/home/ubuntu/.claude
- C:/Users/Mario/.claude.json:/home/ubuntu/.claude.json
- C:/Users/Mario/.git-credentials:/home/ubuntu/.git-credentials
```

> Se uno di questi file o cartelle non esiste ancora sul tuo PC, **crealo vuoto prima di avviare il container**, altrimenti Docker creerà al loro posto una cartella vuota di proprietà di root e ti darà fastidio. In particolare per i file (`.claude.json`, `.git-credentials`) crea un file vuoto con `touch` (Linux/Mac) o "Nuovo file di testo" (Windows) prima di partire.

---

## Usare un file `.env`

Invece di modificare il `compose.yml`, puoi mettere le variabili in un file `.env` nella stessa cartella:

```env
GIT_USER=Mario Rossi
GIT_MAIL=mario.rossi@example.com
PROMPT_TAG=mio-progetto
GRANT_PERMISSION=1000
WORKSPACE_UMASK=002
```

`docker compose` lo legge automaticamente all'avvio.

---

## Comandi utili

```bash
# Avvia il container in background
docker compose up -d

# Entra nel container (apre una shell bash)
docker compose exec --user ubuntu-env bash

# Vedi i log
docker compose logs -f

# Ferma il container
docker compose down

# Forza il pull dell'immagine più recente da GHCR
docker compose pull

# Ricrea il container con l'immagine appena scaricata
docker compose up -d --force-recreate
```

---

## Aggiornamento dell'immagine

L'immagine viene rigenerata automaticamente ogni notte su GitHub. Per scaricare la versione più aggiornata:

```bash
docker compose pull
docker compose up -d --force-recreate
```

---

## Problemi frequenti

**"permission denied" sui file in `/workspace`**
Aggiungi il GID del tuo utente Linux a `GRANT_PERMISSION`. Su Windows/macOS questo problema non dovrebbe verificarsi grazie a Docker Desktop.

**Su Windows il container è lentissimo a leggere/scrivere i file**
Sposta il tuo progetto da `C:\Users\...` a una cartella dentro WSL (es. `\\wsl$\Ubuntu\home\tuoutente\progetti\...`) e lancia `docker compose` da dentro WSL. La differenza di velocità è enorme.

**"unauthorized" quando scarico l'immagine da `ghcr.io`**
Se l'immagine è privata devi autenticarti:
```bash
docker login ghcr.io -u TUO_UTENTE_GITHUB
```
e usare un Personal Access Token GitHub con permesso `read:packages` come password.

**Le mie credenziali Claude / Git non vengono trovate dentro il container**
Controlla che i path nei volumi puntino davvero a file/cartelle esistenti sul tuo PC, e che siano leggibili dal tuo utente. Vedi la sezione "Adattare i percorsi".
