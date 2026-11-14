# D. Photo Watch Lab

App Android che migliora le foto degli orologi da mettere in vendita.
Tutto avviene **sul telefono**: nessun caricamento, nessuna chiave, funziona anche offline.

## Cosa fa (v0.1)
- **Migliora in un tocco**: bilanciamento del bianco (toglie la dominante gialla o blu),
  livelli automatici, ombre e luci, contrasto, riduzione del rumore che tiene i bordi, nitidezza.
- **Quadrante**: posizioni un cerchio sul quadrante (trascini, pizzichi per ridimensionare) e solo lì dentro:
  - **Dettaglio**: chiarezza locale senza aloni attorno a lancette e indici;
  - **Anti-riflesso vetro**: toglie il velo lattiginoso del riflesso, lasciando brillanti indici e lancette;
  - **Togli polvere**: elimina i puntini isolati, senza toccare scritte, indici e bordi.
- **Sfondo bianco**: porta uno sfondo chiaro (foglio bianco o grigio) al bianco pulito, mai dentro il quadrante.
- **Ritaglio 1:1** centrato sul quadrante, per annunci e Instagram.
- Tieni premuto sulla foto per vedere l'originale.
- **Salva** in galleria (album "D. Photo Watch Lab") o **Condividi** direttamente.

## Limiti
- Non è un'IA generativa: non inventa dettagli che la foto non ha. Una foto mossa o molto sfocata migliora poco.
- "Sfondo bianco" funziona su sfondi già chiari e poco colorati, non scontorna sfondi qualsiasi.
- La foto salvata ha il lato lungo massimo di 2400 px (più che sufficiente per Vinted, Subito, eBay, Chrono24).
- "Togli polvere" lavora su puntini piccoli; graffi lunghi o macchie grandi restano.

## Come si costruisce
L'APK viene compilato da GitHub Actions a ogni push su `main` e pubblicato nelle Releases.
La logica del ritocco (`lib/core/`) è Dart puro ed è verificata dai test in `test/`.

un'app Dom Studio
