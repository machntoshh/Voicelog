<div align="center">

<img src="tools/icon_preview.png" width="112" alt="Ícone do VoiceLog" />

# VoiceLog

**Diário de voz pessoal, privado e pesquisável, inspirado em gravadores de detetive.**

Grave uma ideia em um toque, organize em pastas e encontre depois pelo nome, pela data ou **pelas palavras que você falou**, com transcrição feita no próprio dispositivo.

![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart&logoColor=white)
![Android](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white)
![Privacidade](https://img.shields.io/badge/dados-100%25%20locais-2ea44f)
[![Licença: MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-yellow)](LICENSE)

</div>

<p align="center">
  <img src="docs/screenshots/gravando.png" width="200" alt="Gravando" />
  <img src="docs/screenshots/player.png" width="200" alt="Player" />
  <img src="docs/screenshots/transcricao.png" width="200" alt="Transcrição" />
  <img src="docs/screenshots/recuperada.png" width="200" alt="Gravação recuperada" />
</p>

## Funcionalidades

- 🎙️ **Gravação instantânea:** um botão vermelho sempre visível, com cronômetro, forma de onda ao vivo, pausar, retomar e finalizar.
- 🔒 **Grava em segundo plano (Android):** continua com a tela bloqueada ou em outro app, via *Foreground Service* de microfone com notificação.
- 🛟 **Nada se perde:** o áudio é gravado direto no disco em AAC/ADTS. Se o app fechar ou travar no meio, a gravação é **recuperada** na próxima abertura. Fechar a janela de salvamento também não descarta o áudio.
- 🗂️ **Pastas:** crie, renomeie e exclua pastas. Mova gravações arrastando (mouse no PC, toque longo no celular) ou pelo menu **Mover para pasta**. O arquivo nunca é duplicado.
- ▶️ **Player:** barra de progresso com a forma de onda, ±10 s, velocidade de 0,75× a 2×, renomear, exportar/compartilhar e excluir com confirmação.
- 📝 **Transcrição local (opcional):** fala em texto em português com **Whisper**, rodando no aparelho, sem enviar áudio para a internet. Cada trecho mostra o minuto em que foi dito, e tocar nele leva o áudio até lá.
- 🔎 **Pesquisa por conteúdo:** busque por nome, pasta, data, hora ou **o que foi dito**, sem diferenciar acentos ("reuniao" encontra "reunião"). O resultado mostra o trecho e abre o áudio no ponto certo.
- 🌙 **Visual escuro e compacto:** grafite, vermelho suave para gravação e layout responsivo (barra lateral no PC, faixa de pastas no celular).

## Privacidade e LGPD

O VoiceLog foi feito para **não tratar dados pessoais fora do seu dispositivo**, de acordo com a Lei Geral de Proteção de Dados (Lei nº 13.709/2018):

| Princípio | Como o app atende |
|---|---|
| **Necessidade / minimização** | Não há cadastro, conta, login, analytics, telemetria nem anúncios. O app não coleta nenhum dado sobre o usuário. |
| **Finalidade e transparência** | Áudios, transcrições e metadados ficam **somente no dispositivo**, em `Documentos\VoiceLog\` (Windows) ou no armazenamento interno do app (Android). |
| **Segurança** | Nenhum áudio ou texto é enviado a servidores. A transcrição roda localmente. Os modelos baixados têm a integridade conferida por SHA-256. |
| **Livre acesso e eliminação** | O usuário vê, exporta e exclui qualquer gravação a qualquer momento. Desinstalar o app (Android) ou apagar a pasta `VoiceLog` (Windows) remove tudo. |

**Única conexão de rede:** o download opcional do modelo de transcrição, uma única vez e só depois de confirmação explícita. Ele busca **apenas arquivos de modelo** no [Hugging Face](https://huggingface.co/csukuangfj) e no [GitHub](https://github.com/k2-fsa/sherpa-onnx/releases). Como em qualquer download, esses serviços veem o endereço IP de quem baixa.

> ⚠️ **Gravar outras pessoas:** se você registrar a voz de terceiros, você é responsável por ter base legal para isso (por exemplo, o consentimento delas). O app não envia essas gravações a ninguém, mas o conteúdo e o uso delas são seus.

**Este repositório** não contém dados pessoais: nenhuma gravação real, caminho local, credencial ou chave de assinatura. O áudio de teste (`integration_test/fixtures/fala_ptbr.wav`) é uma **voz sintética** gerada por texto-para-fala.

## Tecnologia

| Camada | Escolha |
|---|---|
| App | [Flutter](https://flutter.dev) 3.47 / Dart 3.13 (Android + Windows com o mesmo código) |
| Gravação | [`record`](https://pub.dev/packages/record) (MediaCodec / Media Foundation) em stream AAC-LC 64 kbps → arquivo ADTS |
| Segundo plano | Foreground Service nativo em Kotlin (`foregroundServiceType="microphone"`) |
| Reprodução | [`audioplayers`](https://pub.dev/packages/audioplayers) |
| Transcrição | [`sherpa_onnx`](https://pub.dev/packages/sherpa_onnx) (Whisper + Silero VAD) e [`audio_decoder`](https://pub.dev/packages/audio_decoder) |
| Persistência | `library.json` com escrita atômica (temporário + rename + backup) |

Os detalhes de cada decisão (formato de áudio, recuperação após falhas, segundo plano, pipeline de transcrição) estão em **[ARCHITECTURE.md](ARCHITECTURE.md)**.

### Modelos de transcrição

| Modelo | Download | Perfil |
|---|---|---|
| Whisper small (int8) | 376 MB | Mais preciso em pt-BR, com pontuação |
| Whisper base (int8) | 161 MB | Cerca de 3× mais rápido, para celulares simples |

Medido com 16 s de fala em português: o base levou 2,3 s e o small 6,6 s num PC desktop de 8 núcleos, e o base levou 3,5 s num emulador Android. Os dois transcreveram o texto sem erros.

## Como rodar

### Pré-requisitos

- [Flutter](https://docs.flutter.dev/get-started/install) 3.47 ou mais recente
- **Windows:** Visual Studio 2022+ ou Build Tools com *Desenvolvimento para desktop com C++*, e o **Modo de Desenvolvedor** do Windows ativado (necessário para os plugins)
- **Android:** JDK 17 ou 21, Android SDK (platform 36, build-tools 36) e NDK 28.2. O Gradle baixa o que faltar.

Confira com:

```bash
flutter doctor
```

### No computador (Windows)

```bash
git clone https://github.com/<seu-usuario>/voicelog.git
cd voicelog
flutter pub get
flutter run -d windows
```

Versão de release: `flutter build windows --release` gera `build\windows\x64\runner\Release\voicelog.exe`. Para distribuir, copie a pasta `Release` inteira.

### No Android

```bash
flutter build apk --release --split-per-abi
```

| APK | Tamanho | Para |
|---|---|---|
| `app-arm64-v8a-release.apk` | ~44 MB | A grande maioria dos celulares atuais |
| `app-armeabi-v7a-release.apk` | ~33 MB | Aparelhos antigos de 32 bits |
| `app-x86_64-release.apk` | ~49 MB | Emulador |

Para instalar com o celular conectado (depuração USB ativada):

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

> O build de release usa a chave de depuração, o que basta para instalar e testar. Para publicar na Play Store, crie uma keystore própria e configure `signingConfigs` em `android/app/build.gradle.kts`. **Nunca suba a keystore nem o `key.properties` para o GitHub.** O `.gitignore` já bloqueia esses arquivos.

## Testes

```bash
flutter test
```

**27 testes** de unidade e de interface: persistência ao fechar e reabrir, recuperação de gravação interrompida, adoção de áudios órfãos, fallback para backup se o `library.json` corromper, mover sem duplicar, exclusão de pastas, pesquisa sem acentos e por fala, parser ADTS, leitor WAV e layout desktop/celular.

Testes de integração no dispositivo real:

```bash
# grava pelo microfone: gravar, pausar, retomar, finalizar, reabrir, tocar e decodificar
flutter test integration_test/record_flow_test.dart -d windows

# transcreve fala em pt-BR com o Whisper (baixa o modelo base uma vez)
flutter test integration_test/transcription_test.dart -d windows
flutter test integration_test/transcription_test.dart -d windows --dart-define=MODEL=whisper-small
```

<details>
<summary>Rodando os testes de integração no Android</summary>

O teste de transcrição precisa do áudio de exemplo dentro do app (build de debug):

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb push integration_test/fixtures/fala_ptbr.wav /data/local/tmp/
adb shell run-as dev.voicelog.voicelog cp /data/local/tmp/fala_ptbr.wav app_flutter/
flutter test integration_test/transcription_test.dart -d <id-do-dispositivo>
```

O `flutter test` desinstala o app ao terminar, o que apaga as gravações e as permissões do aparelho de teste.

</details>

## Estrutura

```
lib/
  data/        persistência (LibraryStore), leitura de ADTS
  services/    gravador, ponte com o Android, transcrição e modelos
  ui/          tema, Home, barra de gravação, player, diálogos
android/       Foreground Service de microfone (Kotlin), ícones adaptáveis
windows/       runner Win32 e ícone
integration_test/  testes no dispositivo real + áudio sintético de teste
tools/make_icon.py gera os ícones de Windows e Android
```

## Status

| Etapa | Situação |
|---|---|
| 1. Estrutura e interface | ✅ Concluída |
| 2. Gravador, salvamento e reprodução | ✅ Concluída (verificado no Windows e no Android) |
| 3. Pastas, mover, renomear e pesquisa | ✅ Concluída |
| 4. Android: segundo plano, permissões e APK | ✅ Verificado em emulador Android 15 (tela bloqueada, outro app, encerramento forçado) · ⏳ falta validar em aparelho físico: ligação durante a gravação, reinício do celular, permissão negada e exportação |
| 5. Transcrição e pesquisa por fala | ✅ Concluída (Windows e emulador Android) · ⏳ falta medir o desempenho em celular ARM real |
| 6. Revisão final | 🔄 Em andamento |

### Limitações conhecidas

- No Android, deslizar o app para fora dos recentes encerra a gravação. O que já foi gravado fica salvo.
- A transcrição roda com o app aberto. Se o sistema fechar o app no meio, ela aparece como falha e pode ser repetida.
- O motor ONNX aumenta o tamanho do APK. Por isso a recomendação é usar o APK por arquitetura.

## Licença

Distribuído sob a licença **MIT**. Você pode usar, copiar, modificar e distribuir o código, inclusive comercialmente, desde que mantenha o aviso de copyright. Veja [LICENSE](LICENSE).

Os modelos Whisper ([OpenAI](https://github.com/openai/whisper), MIT) e Silero VAD ([snakers4](https://github.com/snakers4/silero-vad), MIT) **não fazem parte deste repositório**: o app os baixa sob demanda, e cada um segue a sua própria licença.
