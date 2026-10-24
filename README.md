# 🎵 normalizza-mp3

Normalizzatore di volume per file MP3 basato su **FFmpeg / loudnorm (EBU R128)**.
Preserva **tag ID3, copertine e metadati** durante la normalizzazione.

Ideale per:
- 🚗 Musica per **Android Auto / CarPlay** (volume uniforme in auto)
- 🎧 **Audiolibri e podcast**
- 📻 Librerie musicali con volumi molto diversi tra loro

**Versione**: 2.0.0

---

## ✨ Caratteristiche

- ✅ **Preserva i metadati**: tag ID3, copertine, artista, titolo, album
- ✅ **Standard EBU R128** via filtro `loudnorm` di FFmpeg (two-pass)
- ✅ **4 profili predefiniti** + modalita custom
- ✅ **Dry-run** con report dettagliato su file (nessuna modifica)
- ✅ **Ricorsivita** opzionale per includere sottocartelle
- ✅ **Esclusioni** tramite file di testo (salta file specifici)
- ✅ **Check bitrate anomalo** per rilevare file corrotti
- ✅ **Log automatico** sempre generato con dettagli per file
- ✅ **Setup automatico di FFmpeg**: nessuna installazione manuale richiesta
- ✅ **Modalita interattiva** guidata (selezione cartella con dialog)
- ✅ **Modalita CLI** per script e automazioni
- ✅ **Non tocca il PATH di sistema**: FFmpeg scaricato in `.\tools\`

---

## 🚀 Quick start

### 1. Clona il repo

```powershell
git clone https://github.com/TUO-USER/MP3_Normalizza.git
cd MP3_Normalizza
```

### 2. Sblocca lo script (una tantum)

Windows blocca gli script scaricati da Internet:

```powershell
Unblock-File .\normalizza.ps1
```

### 3. Setup automatico di FFmpeg

```powershell
.\normalizza.ps1 -Setup
```

Scarica FFmpeg (~80 MB) in `.\tools\ffmpeg\bin`. **Non modifica nulla di sistema.**

### 4. Dry-run di prova (consigliato la prima volta)

```powershell
.\normalizza.ps1 -InputPath "C:\Musica" -Preset per-auto -DryRun
```

Genera un report in `Normalizzati\dryrun_*.txt` **senza toccare nessun file**.

### 5. Normalizza!

```powershell
# Modalita interattiva guidata (consigliato la prima volta)
.\normalizza.ps1

# Oppure direttamente in CLI
.\normalizza.ps1 -InputPath "C:\Musica" -Preset per-auto -Bitrate 320k
```

Su Windows puoi anche **doppio-click su `avvia.bat`** per lanciare la modalita interattiva.

---

## 🎚️ Profili di volume

| Preset       | Target LUFS | Descrizione                                              |
|--------------|-------------|----------------------------------------------------------|
| `per-auto`   | **-15.0**   | Volume alto, ideale per Android Auto in ambienti rumorosi |
| `podcast`    | **-16.0**   | Podcast, audiolibri                                      |
| `standard`   | **-14.0**   | Standard Spotify / YouTube                               |
| `dinamico`   | **-18.0**   | Preserva differenze soft/forte tra brani                 |
| `custom`     | libero      | Da -10 a -30 LUFS                                        |

---

## 📖 Utilizzo dettagliato

### Modalita interattiva (nessun parametro)

```powershell
.\normalizza.ps1
```

Viene mostrato un menu guidato:

1. Verifica FFmpeg (con auto-setup se mancante)
2. Selezione cartella MP3 (dialog di Windows)
3. Scelta modalita ricorsiva (sottocartelle si/no)
4. Scelta profilo volume
5. Scelta bitrate (128/192/256/320 kbps)
6. Scelta cartella output (sottocartella o sostituzione)
7. Scelta modalita (normalizza o dry-run)
8. Riepilogo + conferma

### Modalita CLI

```powershell
.\normalizza.ps1 -InputPath "C:\Musica\Album" -OutputPath "C:\Musica\Album\Norm" -Preset per-auto -Bitrate 320k
```

### Dry-run con report

```powershell
# Solo cartella principale
.\normalizza.ps1 -InputPath "C:\Musica" -Preset per-auto -DryRun

# Ricorsivo (include sottocartelle)
.\normalizza.ps1 -InputPath "C:\Musica" -Preset per-auto -DryRun -Recurse
```

Il report viene salvato in `Normalizzati\dryrun_YYYYMMDD_HHMMSS.txt` e contiene:

- Riepilogo (file, durata, tempo stimato, spazio stimato, spazio libero)
- Distribuzione rischio (Basso/Medio/ALTO)
- Dettaglio per file (nome, durata, size, bitrate, rischio, stima)
- File con bitrate anomalo (da riparare)
- File ad alto rischio (da verificare)
- Esclusioni attive (se presenti)

### Esclusioni

Crea un file `escludi.txt` con un pattern per riga:

```
# Commento (righe che iniziano con # vengono ignorate)
22.My_Way.mp3
What A Wonderful World
Kenny G
```

Poi lancia:

```powershell
.\normalizza.ps1 -InputPath "C:\Musica" -Preset per-auto -ExcludeList ".\escludi.txt"
```

I file che matchano i pattern vengono **saltati**. Il match funziona su:
- Nome file esatto
- Path completo
- Frammento (es. "Kenny G" esclude tutti i file con "Kenny G" nel nome)

### Parametri disponibili

| Parametro         | Tipo      | Default                 | Descrizione                     |
|-------------------|-----------|-------------------------|---------------------------------|
| `-InputPath`      | string    | —                       | Cartella con gli MP3            |
| `-OutputPath`     | string    | `<Input>\Normalizzati`  | Cartella di output              |
| `-Preset`         | string    | `per-auto`              | Profilo volume                  |
| `-TargetLUFS`     | double    | `-16.0`                 | Usato solo con `-Preset custom` |
| `-Bitrate`        | string    | `320k`                  | Bitrate MP3 output              |
| `-Interactive`    | switch    | —                       | Forza modalita interattiva      |
| `-Setup`          | switch    | —                       | Esegue solo il setup di FFmpeg  |
| `-SkipSetupCheck` | switch    | —                       | Salta il controllo di FFmpeg    |
| `-ToolsPath`      | string    | `.\tools`               | Cartella dove installare FFmpeg |
| `-DryRun`         | switch    | —                       | Analisi senza modifiche         |
| `-Recurse`        | switch    | —                       | Include sottocartelle           |
| `-ExcludeList`    | string    | —                       | Path al file di esclusioni      |

---

## 📝 Log di normalizzazione

Ad ogni esecuzione viene creato **automaticamente** un file di log nella cartella di output:

```
Normalizzati\
├── brano01.mp3
├── brano02.mp3
└── normalizzazione_20250118_143210.log
```

Il log contiene:

- Header con versione script, data, cartella, target, bitrate, ricorsivo
- Una riga per file con esito (`OK` / `FALLITO` / `ESCLUSO`) e tempo
- Riepilogo finale con conteggi (totale, successi, falliti, esclusi, tempo)
- Elenco dei file falliti (se presenti)

---

## 🧠 Come funziona

Per ogni file MP3 lo script esegue:

1. **Analisi** del loudness con `loudnorm` (passata di misurazione)
2. **Normalizzazione** con i valori misurati
3. **Merge dei metadati** dall'originale al file normalizzato:
   - Tag ID3 (titolo, artista, album, anno)
   - Copertina (`attached_pic`)
   - Versione ID3v2.3 + ID3v1

Il risultato è un MP3 con audio normalizzato **e** metadati intatti.

---

## 🐛 Problemi comuni

**"Impossibile eseguire lo script perché l'esecuzione di script è disabilitata"**

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

**FFmpeg non viene trovato dopo il setup**

Verifica che `.\tools\ffmpeg\bin\ffmpeg.exe` esista. Se no, rilancia `-Setup`.

**Download FFmpeg fallito (proxy/firewall)**

Scarica manualmente da <https://www.gyan.dev/ffmpeg/builds/> e metti
`ffmpeg.exe` + `ffprobe.exe` in `.\tools\ffmpeg\bin\`.

**L'artista è troncato a 30 caratteri in alcuni programmi**

Normale: è il limite del vecchio formato ID3v1. I player moderni (jetAudio, VLC, foobar2000, Android Auto, ecc.) leggono il tag ID3v2 completo e ignorano la limitazione.

**Un file ha un bitrate impossibile (> 400 kbps)**

Il dry-run lo segnala nella sezione "FILE CON BITRATE ANOMALO". Usa un tool tipo EaseUS Fixo per ripararlo prima di normalizzarlo.

**Un brano suona più basso dopo la normalizzazione**

Normale per brani con dinamica molto alta (Sinatra, Armstrong, classica, live). La normalizzazione uniforma il volume percepito, non i picchi. Conserva l'originale accanto al normalizzato e scegli caso per caso.

---

## 📜 Licenza

Codice dello script: **MIT** (vedi `LICENSE`).

FFmpeg è distribuito separatamente secondo la sua licenza (LGPL/GPL).
Viene scaricato al primo setup e la sua licenza è in `tools/ffmpeg/LICENSE.txt`.

---

## 🙏 Crediti

- [FFmpeg](https://ffmpeg.org/) — motore audio
- Build statiche Windows: [gyan.dev](https://www.gyan.dev/ffmpeg/builds/)
- Standard [EBU R128](https://tech.ebu.ch/publications/r128)
- [EaseUS Fixo](https://www.easeus.com/) — riparazione file audio (suggerito per file corrotti)