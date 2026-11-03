# TierS

Jogo de Tier List em grupo, de 2 a 10 jogadores, cada um no próprio celular.
Front em React 19 + Vite + TypeScript + Tailwind v4. Back no Supabase (Postgres, Auth anônimo e Realtime).
Todo o código, as regras e a tabela de formações estão no `README.md`.

## Estado atual

- O projeto Supabase já existe: **tiers**, ref `ptzocorqhjixzlknagus`, região `sa-east-1`, organização "matheuspeixotoo's Org".
- O banco desse projeto **já tem o schema aplicado** (03/11/2026): as 7 migrations de `supabase/migrations/` foram aplicadas pelo MCP da Supabase, com os mesmos nomes dos arquivos. `select count(*) from public.themes` dá 200. A 7ª (`accounts`) cria `profiles`, `matches`, `match_players`, o bucket `avatars` e as RPCs de perfil e ranking.
- O login anônimo **já está ativado** (Authentication > Sign In / Providers > "Allow anonymous sign-ins"). Captcha não foi ativado. **"Confirm email" está desligado** de propósito: o cadastro com e-mail e senha entra na hora, sem e-mail de confirmação (o SMTP padrão do Supabase não entrega para quem não é da equipe). Por isso ainda não existe "Esqueci minha senha".
- Contas são **opcionais**: visitante continua entrando só com apelido. Quem tem conta joga com o nick e a foto do perfil, e o `end_match` grava o resultado em `matches`/`match_players` para histórico e ranking.
- `.env.local` **já existe**, com `VITE_SUPABASE_URL` e a chave publishable (`sb_publishable_...`) em `VITE_SUPABASE_ANON_KEY`. Está no `.gitignore`.
- `npm install` e `npm run build` passam. `npm run dev` sobe em `http://192.168.0.65:5173/` na rede local (o endereço 172.29.x.x que o Vite também lista é de um adaptador virtual, não serve para o celular).
- Teste de 2 jogadores (PC + celular) feito em 03/11/2026: uma rodada completa, com pontuação correta.

## Tarefa: deixar o jogo rodando

Faça nesta ordem e confirme cada passo comigo antes de seguir:

1. **Banco.** Aplique o schema no projeto `ptzocorqhjixzlknagus`. Use uma destas opções, a que estiver disponível:
   - com a Supabase CLI: `npx supabase login`, `npx supabase link --project-ref ptzocorqhjixzlknagus` e `npx supabase db push` (aplica os 6 arquivos de `supabase/migrations/` em ordem);
   - ou rode o arquivo único `supabase/setup_completo.sql`, que equivale aos 6 arquivos (pelo MCP da Supabase com `apply_migration`, ou pelo SQL Editor do painel).
   Depois confira: `select count(*) from public.themes` precisa dar **200**.
2. **Login anônimo.** Ative em Authentication > Sign In / Providers > "Allow anonymous sign-ins". Se não der por ferramenta, me peça para clicar no painel.
3. **Variáveis.** Copie `.env.example` para `.env.local` e preencha `VITE_SUPABASE_URL` (`https://ptzocorqhjixzlknagus.supabase.co`) e `VITE_SUPABASE_ANON_KEY` (a chave anon ou publishable, em Project Settings > API).
4. **Rodar.** `npm install` e `npm run dev`. O Vite sobe com `--host`; me passe o endereço "Network" para abrir no celular (mesma rede Wi-Fi).
5. **Teste rápido.** Crie uma sala de 2 jogadores no PC, entre pelo celular com o código e jogue uma rodada.
6. **Publicar (opcional).** Para jogar com gente fora da minha rede: `npm run build` e publicar a pasta `dist` no Netlify ou na Vercel com as duas variáveis de ambiente.

## Regras para mexer no código

- Não edite as migrations que já existem. Mudança no banco vira um arquivo novo em `supabase/migrations/` e, se for o caso, atualize também `supabase/setup_completo.sql`.
- Toda escrita no banco passa pelas funções RPC (`security definer`). As tabelas não têm policy de insert/update/delete de propósito.
- Ninguém pode posicionar, mover ou trocar de lugar uma resposta que escreveu. Isso é validado no servidor.
- O layout não pode ter scroll de página, nem no desktop nem no celular.
- Textos da interface em português do Brasil.
- `npm run build` precisa passar sem erro antes de qualquer entrega.
