# Changelog

Tutte le modifiche rilevanti a questo progetto sono documentate qui.
Formato basato su [Keep a Changelog](https://keepachangelog.com/it/1.1.0/).
Versioning basato su [SemVer](https://semver.org/lang/it/).

## [2.0.0] - 2025-01-18

### Added
- **Dry-run** con `-DryRun`: analisi completa senza modificare nulla
- **Report dry-run su file**: `Normalizzati\dryrun_YYYYMMDD_HHMMSS.txt`
- **Ricorsivita** opzionale con `-Recurse` per includere sottocartelle
- **Esclusioni** con `-ExcludeList`: salta file specifici tramite file di testo
- **Check bitrate anomalo** nel dry-run: rileva file con bitrate stimato > 400 kbps
- **Sezione "FILE CON BITRATE ANOMALO"** nel report: elenco dei file da riparare
- **Colonna Bitrate** nel dettaglio file del report
- **Colonna Rischio** (Basso/Medio/ALTO) basata su durata, nome file, bitrate
- **Sezione "ESCLUSIONI ATTIVE"** nel report: mostra i pattern caricati
- **Conteggio esclusi** nel riepilogo finale e nel log
- **Stima tempo** per file basata su durata: `durata/11 + 2` secondi
- **Stima spazio output** basata su bitrate × durata
- **Verifica spazio libero** su disco con warning se insufficiente
- **Modalita interattiva aggiornata**: chiede ricorsivita e dry-run/normalizza

### Changed
- Versione script portata a 2.0.0
- Euristica Rischio raffinata: rimosso "remaster" (falso positivo), "live" solo se contestualizzato
- Soglia durata per "Medio" portata da 5 a 6 minuti
- Report dry-run piu dettagliato con bitrate e motivi del rischio

### Fixed
- Rilevamento file con header corrotto (bitrate impossibile > 400 kbps)
- Documentazione del limite ID3v1 a 30 caratteri

## [1.0.0] - 2025-01-15

### Added
- Normalizzazione EBU R128 tramite FFmpeg loudnorm (two-pass)
- Preservazione completa di tag ID3, copertine e metadati
- 4 profili volume predefiniti + modalita custom
- Modalita interattiva guidata con dialog Windows
- Modalita CLI per automazioni
- Setup automatico di FFmpeg in .\tools\ffmpeg\bin
- Rilevamento automatico FFmpeg (PATH di sistema o locale)
- Launcher avvia.bat per doppio click
- Supporto profili bitrate 128/192/256/320 kbps
- Log di normalizzazione sempre attivo