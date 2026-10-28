# Capturas de ecrã

O `README.md` principal espera estes ficheiros nesta pasta:

| Ficheiro | O que mostrar |
| --- | --- |
| `mobile-home.png` | Ecrã inicial do telemóvel, com o campo do link e o cartão de destino |
| `mobile-playlist.png` | Playlist carregada: capa, «Reproduzir/Aleatório», lista numerada e mini-player |
| `mobile-now-playing.png` | Ecrã «A reproduzir», com a onda de áudio |
| `desktop-library.png` | Janela desktop com a barra lateral, a lista de faixas e a barra de reprodução |
| `desktop-player.png` | Reprodutor imersivo em ecrã inteiro |

## Como capturar

- **iPhone (simulador):** `Cmd + S` guarda a imagem no ambiente de trabalho.
- **Android (emulador):** botão de câmara na barra do emulador, ou `adb exec-out screencap -p > mobile-home.png`.
- **macOS:** `Cmd + Shift + 4`, depois `Espaço` e clique na janela da app. Isto inclui a sombra da janela.

Dicas:

- Use uma playlist real, com várias faixas já baixadas, para a lista e o reprodutor aparecerem completos.
- Para o desktop, mantenha a janela à volta de 1120×740 (o tamanho inicial da app).
- Largura sugerida: 1000–1400 px para o desktop e cerca de 400 px para o mobile. O GitHub reduz imagens maiores.
- Pode comprimir os PNG com [squoosh.app](https://squoosh.app) ou `pngquant` para o repositório ficar leve.
