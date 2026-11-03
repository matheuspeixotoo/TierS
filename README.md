<div align="center">

<img src="public/icon.svg" width="96" alt="Ícone do TierS" />

# TierS

**O jogo de Tier List em grupo.** Cada jogador recebe um Tier secreto (S, A, B, C ou F), escreve algo do tema sorteado que combine com ele, e o grupo tenta montar a Tier List perfeita. De 2 a 10 jogadores, cada um no seu celular.

[![Jogar agora](https://img.shields.io/badge/Jogar_agora-tiers--jogo.netlify.app-FFD93D?style=for-the-badge&logo=netlify&logoColor=2B1A63&labelColor=2B1A63)](https://tiers-jogo.netlify.app)

![React 19](https://img.shields.io/badge/React-19-61DAFB?logo=react&logoColor=white)
![Vite](https://img.shields.io/badge/Vite-8-646CFF?logo=vite&logoColor=white)
![TypeScript](https://img.shields.io/badge/TypeScript-5.9-3178C6?logo=typescript&logoColor=white)
![Tailwind CSS v4](https://img.shields.io/badge/Tailwind_CSS-v4-06B6D4?logo=tailwindcss&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-Postgres_·_Auth_·_Realtime-3FCF8E?logo=supabase&logoColor=white)

<img src="docs/home.png" width="800" alt="Tela inicial do TierS: criar sala ou entrar com o código" />

</div>

## Como jogar

1. **Crie uma sala** com o seu apelido e escolha quantas pessoas vão jogar. Compartilhe o código de 4 letras.
2. **Cada um entra pelo celular** com o código e um apelido. A partida começa quando a sala está completa.
3. **Um jogador sorteado escolhe o tema** entre duas opções (ou sorteia de novo, até 3 vezes por partida).
4. **Cada um recebe um Tier secreto** e escreve algo do tema que combine com ele. Quem tirou F escreve algo F mesmo.
5. **Na sua vez, coloque a resposta de alguém no quadro.** Você nunca mexe na própria resposta.
6. **Ajustes:** cada um pode subir ou descer uma resposta em 1 nível (ou passar).
7. **Revelação:** acerto vale +1, erro vale −1. Se o time gabaritar, todo mundo ganha +2.

Sem cadastro, sem app pra instalar: abre no navegador do celular e pronto.

**Jogue em [tiers-jogo.netlify.app](https://tiers-jogo.netlify.app).**

## Formações

O host escolhe quantas pessoas vão jogar ao criar a sala (dá pra mudar na sala de espera). A partida só começa com a sala completa, e a formação depende desse número:

| Jogadores | Tiers no quadro | Respostas por Tier | Respostas por jogador |
|---|---|---|---|
| 2 | S A B C F | 2 | 5, uma de cada Tier |
| 3 | S B F | 3 | 3 |
| 4 | S A B F | 2 | 2 |
| 5 | S A B C F | 2 | 2 |
| 6 | S B F | 4 | 2 |
| 7 | S A B F | 2 | 1 (um jogador escreve 2, revezando a cada rodada) |
| 8 | S A B F | 2 | 1 |
| 9 | S A B C F | 2 | 1 (um jogador escreve 2, revezando a cada rodada) |
| 10 | S A B C F | 2 | 1 |

Com até 4 jogadores, os ajustes têm 2 voltas. Subir ou descer 1 nível considera só os Tiers do quadro: com S, B e F, subir do B vai direto pro S.

## Como funciona

- **Servidor manda nas regras.** Todo movimento (entrar na sala, posicionar, mover, revelar, pontuar) é uma função SQL (`security definer`) que valida a vez, o dono da resposta e o limite de 2 respostas por Tier. O app não consegue escrever direto nas tabelas.
- **Tier secreto de verdade.** O Tier de cada resposta fica em `card_secrets`, que cada jogador só consegue ler para a própria resposta. Os Tiers só aparecem para todos quando o host revela.
- **Só o host vê o código da sala.** O código fica em `room_codes`, legível apenas pelo host, que é quem compartilha. Se o host sair da sala de espera, o próximo jogador vira host.
- **Sincronização.** Cada jogada incrementa `rooms.version`. Os aparelhos escutam essa linha pelo Realtime e buscam o estado completo com `get_state`. Um polling a cada 5 s cobre conexões que caem.
- **Escolha do tema.** A cada rodada, um jogador sorteado (nunca o mesmo da rodada anterior) recebe 2 opções de tema e escolhe uma. Só ele vê as opções. Cada jogador tem 3 "Sortear novamente" por partida, que trocam as duas opções. Sem nenhum sobrando, ele escolhe entre as que vieram. Quem zera ganha 1 de volta 5 rodadas depois de zerar (zerou na rodada 4, recebe na 9). Quem ainda tem algum não ganha nada. Se quem escolhe sumir, o host pode sortear outra pessoa.
- **Pontuação por rodada.** +1 por resposta posicionada no Tier certo e −1 no errado. +1 por ajuste que aproxima a resposta do Tier real e −1 por ajuste que afasta. Se o time gabaritar, todo mundo ganha +2. O placar soma entre rodadas até o host encerrar a partida.
- **Sua resposta é intocável por você.** Ninguém posiciona, move ou troca de lugar uma resposta que escreveu, senão ficaria fácil colocar as próprias no Tier certo.
- **Jogador sumiu?** O host pode pular a vez de quem travou o posicionamento ou os ajustes.

## Estrutura

```
supabase/migrations/   schema, segurança e regras do jogo (SQL)
src/lib/               cliente Supabase, chamadas RPC, tipos e constantes
src/hooks/useRoom.ts   sincronização em tempo real da sala
src/screens/           Home, Lobby, Deal (sorteio), Write, Game, Final
src/components/        UI compartilhada (logo, avatares, ranking, modal)
docs/                  imagens do README
```

## Temas

O jogo vem com 200 temas, de "Filmes de comédia" a "Tipos de parente na festa de família". A cada rodada o jogador sorteado recebe 2 deles para escolher.

## Limitações conhecidas

- Não dá para entrar numa partida que já começou. A pessoa espera o host encerrar e abrir uma nova.
- Se alguém sumir na fase de escrever a resposta, a rodada fica esperando. Nas fases de posicionar e ajustar, o host pode pular a vez.
- Se o host sair do jogo no meio da partida, ninguém consegue avançar a rodada.

## Licença

**Todos os direitos reservados.** O código está aberto para leitura, mas não há permissão para usar, copiar, modificar, hospedar ou redistribuir este software, no todo ou em parte. Quer jogar? É em [tiers-jogo.netlify.app](https://tiers-jogo.netlify.app). Veja o arquivo [LICENSE](LICENSE).
