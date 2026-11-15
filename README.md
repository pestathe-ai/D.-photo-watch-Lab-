# D. Photo Watch Lab

App Android che migliora le foto degli orologi da mettere in vendita.
Tutto avviene **sul telefono**: nessun caricamento, nessuna chiave, funziona anche offline.

## Novità v0.5
- **Anti-riflesso forte** (scheda Quadrante): toglie il velo chiaro che il riflesso del
  cielo o di una finestra stende sui quadranti scuri. Parte da zero e si regola a mano
  (sui quadranti chiari va lasciato a zero). Le macchie vere del quadrante restano visibili:
  l'app non nasconde i difetti dell'orologio.

## Novità v0.4
- **Stile "Ricco"** (nuovo "Migliora in un tocco"), ricavato dalle foto ritoccate a mano
  dall'utente: toni profondi, cinturino più vivo, oro caldo, sfondo scuro pulito
  (meno grana, via i pelucchi del velluto), nitidezza solo sui bordi veri.
  Non inventa dettagli: scritte e numeri del quadrante restano quelli veri.
  Resta disponibile lo stile "Naturale".
- **Quadrante di qualsiasi forma**: trovato da solo anche se è rettangolare o tonneau
  (provato su 7 foto reali di un Citizen rettangolare: 7 su 7).
- **Tocca il quadrante (IA di Google)**: MediaPipe MagicTouch, scaricato una volta
  (~6 MB) e poi usato sul telefono, offline. Tocchi il quadrante e ne trova il contorno.
- Nuovi cursori: Tono ricco, Chiarezza, Vivacità, Pulisci sfondo scuro.
- Interno dell'app di nuovo blu (l'icona resta rossa).

## Novità v0.3
- **Ritocco naturale**: "Migliora in un tocco" ora corregge luce e colore con delicatezza
  e **ammorbidisce** graffietti e micro-segni sul quadrante invece di evidenziarli
  (indici, lancette e scritte restano nitidi). Nitidezza leggera solo sui bordi veri.
- **Intensità**: un cursore per decidere quanto ritoccare.
- **Scontorno IA di Google** (ML Kit, sul telefono): riconosce l'orologio e schiarisce solo
  lo sfondo, anche se non è bianco, tenendo un filo d'ombra naturale. Il modello arriva da
  Google Play (la prima volta serve internet), poi funziona offline. Se non è disponibile,
  l'app usa il metodo semplice di prima.
- "Dettaglio" del quadrante ora parte da zero: rende più incisi indici e scritte ma mostra i difetti.
- App e icona **rosse**.

## Novità v0.2
- **Più foto insieme**: selezioni fino a 30 foto, le migliora tutte in automatico e le salva
  o condivide in un colpo. Tocchi una foto per ritoccarla a mano, poi "Applica a tutte"
  copia le stesse regolazioni sulle altre.
- **Quadrante trovato da solo** in ogni foto (anche in quella singola). Se non lo trova,
  la foto ha un segnale arancio e il cerchio lo posizioni tu.
- **Foto meno fredde**: il bilanciamento del bianco corregge solo in parte la luce calda,
  e "Migliora in un tocco" lascia un filo di calore.

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
- Il quadrante si trova meglio su foto frontali o di tre quarti; se sbaglia, "Tocca il quadrante (IA)" o trascina il contorno.
- "Tocca il quadrante (IA)" richiede internet solo la prima volta, per scaricare il modello.
- Non è un'IA generativa: non inventa dettagli che la foto non ha. Una foto mossa o molto sfocata migliora poco.
- "Sfondo bianco" funziona su sfondi già chiari e poco colorati, non scontorna sfondi qualsiasi.
- La foto salvata ha il lato lungo massimo di 2400 px (più che sufficiente per Vinted, Subito, eBay, Chrono24).
- "Togli polvere" lavora su puntini piccoli; graffi lunghi o macchie grandi restano.

## Come si costruisce
L'APK viene compilato da GitHub Actions a ogni push su `main` e pubblicato nelle Releases.
La logica del ritocco (`lib/core/`) è Dart puro ed è verificata dai test in `test/`.

un'app Dom Studio
