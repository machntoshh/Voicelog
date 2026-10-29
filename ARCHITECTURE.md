# Arquitetura do VoiceLog

## Tecnologia

**Flutter 3.47 (Dart 3.13)**, com código nativo Kotlin no Android onde a
plataforma exige.

| Alternativa | Por que não |
|---|---|
| Compose Multiplatform | Ótimo no Android, mas a captura de áudio no desktop (JVM/javax.sound) é fraca e a distribuição é mais pesada. |
| React Native | A gravação em segundo plano depende de módulos de terceiros pouco mantidos. Não traz ganho sobre Flutter + Kotlin. |
| Capacitor / Tauri / PWA | Áudio via WebView, com limitações sérias de gravação em segundo plano no Android. |

Flutter dá um único código para Android e Windows. O plugin
[`record`](https://pub.dev/packages/record) usa MediaCodec no Android e
MediaFoundation no Windows, com pausa/retomada, nível de áudio e tratamento de
interrupções. O que ele não cobre (o Foreground Service) é Kotlin próprio, num
arquivo só.

| Dependência | Papel |
|---|---|
| `record` | Captura e codificação AAC-LC |
| `audioplayers` | Reprodução (MediaPlayer no Android, MediaFoundation no Windows), velocidade |
| `path_provider` | Pasta de documentos do app |
| `share_plus` | Exportar/compartilhar no Android |
| `sherpa_onnx` | Whisper e detector de voz (Silero VAD) via ONNX Runtime, no dispositivo |
| `audio_decoder` | Decodifica AAC para PCM 16 kHz mono (MediaCodec no Android, Media Foundation no Windows) |
| `crypto` | SHA-256 dos modelos baixados |

## Estrutura

```
lib/
  main.dart                      inicialização, carrega a biblioteca
  models.dart                    Folder, Recording (JSON)
  format.dart                    datas, durações, nome sugerido, normalização p/ busca
  data/
    library_store.dart           dono do estado: CRUD, consultas, persistência, recuperação
    adts.dart                    leitura de quadros ADTS (duração exata, corte de quadro parcial)
  services/
    recorder_controller.dart     máquina de estados da gravação
    platform_bridge.dart         canal com o Foreground Service do Android
    speech_models.dart           catálogo Whisper (URLs fixadas + SHA-256), download verificado
    transcription_service.dart   fila, decodificação, isolate com VAD + Whisper
  ui/
    theme.dart                   paleta e tema escuro
    home_page.dart               Home responsiva (sidebar ≥ 760 px, faixa de pastas no celular)
    recorder_bar.dart            botão vermelho / controles de gravação
    recording_tile.dart          item da lista, arrastar e soltar, menu de ações
    player_sheet.dart            player
    recording_actions.dart       renomear, mover, exportar, transcrever, excluir
    transcription_settings.dart  escolha/download de modelo, transcrição automática
    dialogs.dart                 salvar, pasta, confirmações
android/app/src/main/kotlin/dev/voicelog/voicelog/
  MainActivity.kt                MethodChannel "voicelog/recording"
  RecordingService.kt            Foreground Service tipo "microphone"
```

O estado vive em três `ChangeNotifier` globais, `LibraryStore`,
`RecorderController` e `TranscriptionService`, expostos por um `InheritedWidget` (`AppScope`). A
gravação não depende de nenhuma tela: o usuário navega, abre o player ou
organiza pastas enquanto grava.

## Gravação confiável

**Formato: AAC-LC 64 kbps mono 44,1 kHz em contêiner ADTS (`.aac`)**, cerca de
29 MB por hora. O áudio chega do plugin como stream e é gravado no arquivo de
forma síncrona, com `fsync` a cada ~5 s. Cada quadro ADTS é independente.
Se o processo morrer, o arquivo continua tocável até o último quadro completo.
Um MP4/M4A ficaria ilegível, porque depende de um índice escrito só no fim.

**Ciclo de vida de um registro:**

1. Ao tocar em gravar, o registro é criado em `library.json` com estado
   `recording` **antes** de capturar qualquer áudio.
2. A gravação acontece com o arquivo crescendo no disco.
3. Ao finalizar, a duração exata é lida dos quadros ADTS, e o registro passa a
   `ready`, em **Sem pasta**.
4. A janela de salvamento só renomeia ou move. Se for fechada, nada se perde.

**Recuperação (`LibraryStore.load`):** registros ainda em `recording` são de
uma sessão que morreu. Se há áudio, o quadro parcial final é cortado, a
duração é calculada e o registro vira "Recuperada" em Sem pasta. Se não há
áudio, o registro é removido. Arquivos `.aac` sem metadados também são
adotados, e o usuário é avisado.

**Persistência atômica:** cada alteração grava `library.json.tmp` com flush,
copia a versão atual para `library.json.bak` e renomeia o temporário por cima.
A leitura tenta `.tmp` (se completo), depois o principal, depois o `.bak`. As
escritas são serializadas numa fila. Mover ou renomear altera só metadados, e o
arquivo de áudio nunca é copiado.

## Segundo plano no Android

- `RecordingService` é um Foreground Service com
  `foregroundServiceType="microphone"`, iniciado pelo toque em gravar (com o app
  em primeiro plano, como o Android 12+ exige). Enquanto ele roda, o sistema
  mantém o processo vivo e libera o microfone com a tela bloqueada ou outro app
  na frente. Ele segura um wake lock parcial e mostra a notificação persistente
  com cronômetro ("Gravando" / "Gravação pausada").
- Permissões: `RECORD_AUDIO` (pedida pelo plugin), `POST_NOTIFICATIONS` (Android
  13+, pedida mas não obrigatória), `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_MICROPHONE` e `WAKE_LOCK`.
- **Interrupções:** chamadas e perda de foco de áudio pausam a gravação
  (`AudioInterruptionMode.pause`), e a interface reflete o estado. Erro do
  microfone ou disco cheio finaliza a gravação e salva o que já foi capturado,
  com mensagem. Com menos de 50 MB livres, a gravação não começa.
- **Limite conhecido:** deslizar o app para fora da lista de recentes encerra o
  motor Flutter e, com ele, a captura. O arquivo fica íntegro, e o serviço se
  encerra (`onTaskRemoved`) para não deixar uma notificação falsa. Se o sistema
  matar o processo, a gravação é recuperada na próxima abertura.
- No Windows não há restrição de segundo plano: a gravação continua com a
  janela minimizada.

## Privacidade

Tudo é local. Não há conta nem telemetria. A única conexão de rede é o download
opcional do modelo de transcrição, que só acontece depois de o usuário
confirmar e só busca arquivos de modelo. Nenhum áudio ou texto é enviado.
Exportar é sempre uma ação explícita do usuário (folha de compartilhamento no
Android, cópia para `Downloads` no Windows). No Android, a permissão
`INTERNET` existe só para esse download.

## Transcrição (Etapa 5)

**Escolha: transcrição local com Whisper, via
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx).** A opção local é viável
nas duas plataformas, então nenhum serviço em nuvem foi usado: não há custo
por minuto nem envio de áudio, e a transcrição funciona sem internet.

| Modelo (int8) | Download | Uso |
|---|---|---|
| Whisper small | 376 MB | Padrão sugerido. Melhor em pt-BR, com pontuação. |
| Whisper base | 161 MB | Cerca de 3× mais rápido. Para celulares simples ou pouco espaço. |

O Whisper large-v3-turbo (1 GB) ficou de fora: é pesado demais para celular.

**Pipeline (`TranscriptionService`):**

1. A gravação entra numa fila, uma por vez, no estado `pending`.
2. O `audio_decoder` decodifica o AAC/ADTS para WAV 16 kHz mono 16 bits num
   arquivo temporário (`<biblioteca>/tmp`), no isolate principal, porque usa um
   canal de plataforma.
3. Num **isolate separado** (a interface continua fluida): o WAV é lido em
   blocos, sem carregar uma hora de áudio na memória, e passa pelo **Silero
   VAD**, que corta a fala em trechos de até 20 s e descarta o silêncio. Cada
   trecho vai para o Whisper com idioma `pt`. O isolate envia o progresso real
   (0–100%).
4. O resultado é salvo em `Recording.transcript` como uma lista de
   `TranscriptSegment(início, texto)`. É isso que permite mostrar o minuto de
   cada trecho e pular o áudio até ele. O arquivo de áudio nunca é tocado.

**Estados:** `none → pending → running → done | failed`. A falha guarda uma
mensagem simples e oferece "Tentar novamente". Se o app fechar no meio,
`LibraryStore.load` marca o estado como `failed` em vez de repetir sozinho:
assim, um modelo que derrube o app não entra em loop.

**Modelos:** os arquivos vêm do Hugging Face (`csukuangfj/sherpa-onnx-whisper-*`,
**fixados numa revisão**) e do GitHub (Silero VAD). Cada arquivo é baixado
para `.part`, conferido por tamanho e **SHA-256** e só então renomeado. Um
arquivo corrompido ou adulterado é descartado. Ficam em
`<biblioteca>/models/<id>/` e podem ser removidos pela tela **CC**.

**Pesquisa por conteúdo:** `LibraryStore.search` exige que cada termo apareça
no nome, na pasta, na data/hora **ou** na transcrição, sem diferenciar acentos.
Quando o termo está na fala, o resultado traz o trecho em volta (com o termo
destacado) e o minuto em que ele começa, e abrir o resultado toca a partir
dali. A busca roda em memória, o que basta para milhares de gravações.

**Limitações conhecidas:**
- A transcrição roda com o app aberto. No Android, se o sistema matar o app
  em segundo plano, ela aparece como falha e pode ser repetida. A gravação, ao
  contrário, tem serviço em primeiro plano próprio.
- O ONNX Runtime aumenta o APK. Por isso a recomendação é o APK por
  arquitetura (`arm64-v8a`, ~44 MB).
- O tempo em celulares ARM reais ainda não foi medido.
