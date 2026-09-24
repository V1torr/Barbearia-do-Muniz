-- ════════════════════════════════════════════════════════════════
-- Studio 97 Barbearia — estrutura do banco
-- SQL Editor > New query > colar tudo > Run
-- ⚠ O bloco RESET apaga as tabelas e TODOS os dados antes de recriar.
-- ════════════════════════════════════════════════════════════════


-- ── RESET ───────────────────────────────────────────────────────

drop table if exists public.agendamentos, public.mensalistas, public.dias_bloqueados, public.admins cascade;
drop function if exists public.is_admin();
drop function if exists public.horarios_ocupados(date, text);


-- ── TABELAS ─────────────────────────────────────────────────────

create table public.agendamentos (
  id               uuid primary key default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  cliente_nome     text not null check (char_length(cliente_nome) between 1 and 120),
  cliente_telefone text not null check (char_length(cliente_telefone) between 8 and 20),
  barbeiro         text not null check (char_length(barbeiro) between 1 and 120),
  servicos         text not null check (char_length(servicos) between 1 and 500),
  total            numeric(10,2) not null default 0 check (total >= 0),
  data_agendamento date not null,
  horario          text not null check (horario ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  status           text not null default 'confirmado'
                   check (status in ('confirmado', 'concluido', 'cancelado', 'excluido'))
);

-- Impede reserva dupla: só um agendamento ativo por barbeiro + data + horário.
-- Cancelados e excluídos liberam o horário.
create unique index agendamentos_horario_unico
  on public.agendamentos (barbeiro, data_agendamento, horario)
  where status in ('confirmado', 'concluido');

create index agendamentos_data_idx on public.agendamentos (data_agendamento);

create table public.mensalistas (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  nome       text not null,
  telefone   text not null,
  barbeiro   text not null,
  observacao text
);

create table public.dias_bloqueados (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  data       date not null unique,
  motivo     text
);

-- Quem é admin. Ter login no Supabase Auth NÃO basta: o usuário precisa estar aqui.
create table public.admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);


-- ── FUNÇÕES ─────────────────────────────────────────────────────

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- Horários ocupados para o site público: devolve só data, horário e barbeiro
-- (nunca nome ou telefone do cliente).
create or replace function public.horarios_ocupados(p_data date, p_barbeiro text default null)
returns table (data_agendamento date, horario text, barbeiro text)
language sql stable security definer
set search_path = ''
as $$
  select a.data_agendamento, a.horario, a.barbeiro
  from public.agendamentos a
  where a.data_agendamento = p_data
    and (p_barbeiro is null or a.barbeiro = p_barbeiro)
    and a.status in ('confirmado', 'concluido')
  order by a.horario;
$$;

revoke all on function public.is_admin() from public;
revoke all on function public.horarios_ocupados(date, text) from public;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.horarios_ocupados(date, text) to anon, authenticated;


-- ── PERMISSÕES DE TABELA ────────────────────────────────────────

revoke all on public.agendamentos, public.mensalistas, public.dias_bloqueados, public.admins
  from anon, authenticated;

grant insert on public.agendamentos to anon;
grant select on public.dias_bloqueados to anon;
grant select, insert, update, delete
  on public.agendamentos, public.mensalistas, public.dias_bloqueados
  to authenticated;


-- ── RLS ─────────────────────────────────────────────────────────

alter table public.agendamentos    enable row level security;
alter table public.mensalistas     enable row level security;
alter table public.dias_bloqueados enable row level security;
alter table public.admins          enable row level security;  -- sem políticas: ninguém acessa pela API

-- Público: só cria agendamento 'confirmado', de hoje em diante. Não lê nada.
create policy "publico cria agendamento"
  on public.agendamentos for insert to anon
  with check (
    status = 'confirmado'
    and data_agendamento >= (now() at time zone 'America/Sao_Paulo')::date
  );

create policy "admin gerencia agendamentos"
  on public.agendamentos for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "admin gerencia mensalistas"
  on public.mensalistas for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "publico le dias bloqueados"
  on public.dias_bloqueados for select to anon
  using (true);

create policy "admin gerencia dias bloqueados"
  on public.dias_bloqueados for all to authenticated
  using (public.is_admin()) with check (public.is_admin());


-- ── CADASTRAR O ADMIN ───────────────────────────────────────────
-- 1. Authentication > Users > Add user > Create new user. No site o admin entra
--    com um nome de usuário (ex.: muniz); aqui use o e-mail muniz@studio97.local,
--    defina a senha e marque "Auto Confirm User".
-- 2. Ajuste o e-mail abaixo (se usou outro usuário) e rode só esta linha:
--
-- insert into public.admins (user_id) select id from auth.users where email = 'muniz@studio97.local';
