-- =====================================================================
-- OrientaPro · 003_rls.sql
-- Row Level Security em 100% das tabelas (RNF04) + permissões por coluna.
-- auth.uid() = id do usuário logado (vem do token JWT).
-- =====================================================================

alter table public.usuarios              enable row level security;
alter table public.empresas              enable row level security;
alter table public.areas_profissionais   enable row level security;
alter table public.curriculos            enable row level security;
alter table public.experiencias          enable row level security;
alter table public.formacoes             enable row level security;
alter table public.habilidades           enable row level security;
alter table public.curriculo_habilidades enable row level security;
alter table public.perguntas_teste       enable row level security;
alter table public.alternativas          enable row level security;
alter table public.testes_vocacionais    enable row level security;
alter table public.respostas_teste       enable row level security;
alter table public.cursos                enable row level security;
alter table public.vagas                 enable row level security;
alter table public.candidaturas          enable row level security;
alter table public.notificacoes          enable row level security;

-- ---------- USUARIOS ----------
-- Cada um vê o próprio perfil; a empresa vê os candidatos das próprias vagas; o admin vê todos.
create policy usuarios_select on public.usuarios for select to authenticated using (
  id_usuario = auth.uid()
  or public.is_admin()
  or exists (select 1 from public.candidaturas c
               join public.vagas v    on v.id_vaga = c.id_vaga
               join public.empresas e on e.id_empresa = v.id_empresa
              where c.id_usuario = usuarios.id_usuario
                and e.id_usuario_responsavel = auth.uid())
);
create policy usuarios_update_proprio on public.usuarios for update to authenticated
  using (id_usuario = auth.uid()) with check (id_usuario = auth.uid());
create policy usuarios_update_admin on public.usuarios for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
-- A inserção é feita só pelo trigger handle_new_user (security definer).
-- Permissões por coluna: o usuário não consegue mudar o próprio tipo, e-mail nem desbloquear a si mesmo.
revoke insert, update on public.usuarios from anon, authenticated;
grant update (nome_completo, telefone, data_nascimento, foto_url) on public.usuarios to authenticated;
grant update (ativo, motivo_bloqueio) on public.usuarios to authenticated;  -- só passa pela policy de admin
-- Observação: um usuário comum poderia tentar alterar "ativo" do próprio registro pela policy
-- usuarios_update_proprio; o trigger abaixo impede isso.
create or replace function public.proteger_campos_usuario()
returns trigger language plpgsql as $$
begin
  if (new.ativo is distinct from old.ativo or new.motivo_bloqueio is distinct from old.motivo_bloqueio)
     and not public.is_admin() then
    raise exception 'Somente o administrador pode bloquear ou desbloquear usuários.';
  end if;
  if new.tipo_usuario = 'ADMIN' and new.ativo = false and old.ativo = true then
    raise exception 'Um administrador não pode ser bloqueado (UC10 · FE01).';
  end if;
  return new;
end $$;
create trigger trg_proteger_usuario before update on public.usuarios
  for each row execute function public.proteger_campos_usuario();

-- ---------- EMPRESAS ----------
create policy empresas_select on public.empresas for select to anon, authenticated using (true);
create policy empresas_insert on public.empresas for insert to authenticated
  with check (id_usuario_responsavel = auth.uid() and verificada = false);
create policy empresas_update_propria on public.empresas for update to authenticated
  using (id_usuario_responsavel = auth.uid()) with check (id_usuario_responsavel = auth.uid());
create policy empresas_update_admin on public.empresas for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
revoke update on public.empresas from anon, authenticated;
grant update (razao_social, nome_fantasia, email_contato, telefone, descricao, logo_url) on public.empresas to authenticated;
grant update (verificada) on public.empresas to authenticated;
create or replace function public.proteger_verificacao_empresa()
returns trigger language plpgsql as $$
begin
  if new.verificada is distinct from old.verificada and not public.is_admin() then
    raise exception 'Somente o administrador verifica empresas (RN08).';
  end if;
  return new;
end $$;
create trigger trg_proteger_empresa before update on public.empresas
  for each row execute function public.proteger_verificacao_empresa();

-- ---------- Catálogos: leitura pública, escrita só do ADMIN ----------
create policy areas_select        on public.areas_profissionais for select to anon, authenticated using (true);
create policy areas_admin         on public.areas_profissionais for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy perguntas_select    on public.perguntas_teste     for select to anon, authenticated using (ativa or public.is_admin());
create policy perguntas_admin     on public.perguntas_teste     for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy alternativas_select on public.alternativas        for select to anon, authenticated using (true);
create policy alternativas_admin  on public.alternativas        for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy cursos_select       on public.cursos              for select to anon, authenticated using (ativo or public.is_admin());
create policy cursos_admin        on public.cursos              for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy habilidades_select  on public.habilidades         for select to anon, authenticated using (true);
create policy habilidades_insert  on public.habilidades         for insert to authenticated with check (public.eu_ativo());

-- ---------- CURRICULOS (RN10) ----------
create policy curriculos_select on public.curriculos for select to authenticated using (
  id_usuario = auth.uid()
  or exists (select 1 from public.candidaturas c
               join public.vagas v    on v.id_vaga = c.id_vaga
               join public.empresas e on e.id_empresa = v.id_empresa
              where c.id_curriculo = curriculos.id_curriculo
                and e.id_usuario_responsavel = auth.uid())
);
create policy curriculos_insert on public.curriculos for insert to authenticated
  with check (id_usuario = auth.uid() and public.eu_ativo());
create policy curriculos_update on public.curriculos for update to authenticated
  using (id_usuario = auth.uid()) with check (id_usuario = auth.uid() and public.eu_ativo());
create policy curriculos_delete on public.curriculos for delete to authenticated
  using (id_usuario = auth.uid());

-- Tabelas filhas: seguem o dono do currículo (e a leitura da empresa via curriculos_select)
create policy experiencias_select on public.experiencias for select to authenticated
  using (exists (select 1 from public.curriculos c where c.id_curriculo = experiencias.id_curriculo));
create policy experiencias_dono on public.experiencias for all to authenticated
  using (exists (select 1 from public.curriculos c where c.id_curriculo = experiencias.id_curriculo and c.id_usuario = auth.uid()))
  with check (exists (select 1 from public.curriculos c where c.id_curriculo = experiencias.id_curriculo and c.id_usuario = auth.uid()));

create policy formacoes_select on public.formacoes for select to authenticated
  using (exists (select 1 from public.curriculos c where c.id_curriculo = formacoes.id_curriculo));
create policy formacoes_dono on public.formacoes for all to authenticated
  using (exists (select 1 from public.curriculos c where c.id_curriculo = formacoes.id_curriculo and c.id_usuario = auth.uid()))
  with check (exists (select 1 from public.curriculos c where c.id_curriculo = formacoes.id_curriculo and c.id_usuario = auth.uid()));

create policy cur_hab_select on public.curriculo_habilidades for select to authenticated
  using (exists (select 1 from public.curriculos c where c.id_curriculo = curriculo_habilidades.id_curriculo));
create policy cur_hab_dono on public.curriculo_habilidades for all to authenticated
  using (exists (select 1 from public.curriculos c where c.id_curriculo = curriculo_habilidades.id_curriculo and c.id_usuario = auth.uid()))
  with check (exists (select 1 from public.curriculos c where c.id_curriculo = curriculo_habilidades.id_curriculo and c.id_usuario = auth.uid()));

-- ---------- TESTES_VOCACIONAIS / RESPOSTAS_TESTE: só o próprio estudante ----------
create policy testes_select on public.testes_vocacionais for select to authenticated using (id_usuario = auth.uid());
create policy testes_insert on public.testes_vocacionais for insert to authenticated
  with check (id_usuario = auth.uid() and public.eu_ativo());
create policy testes_update on public.testes_vocacionais for update to authenticated
  using (id_usuario = auth.uid()) with check (id_usuario = auth.uid());

create policy respostas_select on public.respostas_teste for select to authenticated
  using (exists (select 1 from public.testes_vocacionais t where t.id_teste = respostas_teste.id_teste and t.id_usuario = auth.uid()));
create policy respostas_insert on public.respostas_teste for insert to authenticated
  with check (exists (select 1 from public.testes_vocacionais t where t.id_teste = respostas_teste.id_teste and t.id_usuario = auth.uid()));

-- ---------- VAGAS (RN06, RN08) ----------
create policy vagas_select on public.vagas for select to anon, authenticated using (
  (status = 'ABERTA' and (data_encerramento is null or data_encerramento >= current_date))
  or public.is_admin()
  or exists (select 1 from public.empresas e where e.id_empresa = vagas.id_empresa and e.id_usuario_responsavel = auth.uid())
);
create policy vagas_empresa on public.vagas for all to authenticated
  using (exists (select 1 from public.empresas e where e.id_empresa = vagas.id_empresa and e.id_usuario_responsavel = auth.uid()))
  with check (exists (select 1 from public.empresas e where e.id_empresa = vagas.id_empresa
                        and e.id_usuario_responsavel = auth.uid() and e.verificada));

-- ---------- CANDIDATURAS ----------
create policy candidaturas_select on public.candidaturas for select to authenticated using (
  id_usuario = auth.uid()
  or exists (select 1 from public.vagas v join public.empresas e on e.id_empresa = v.id_empresa
              where v.id_vaga = candidaturas.id_vaga and e.id_usuario_responsavel = auth.uid())
);
create policy candidaturas_insert on public.candidaturas for insert to authenticated
  with check (id_usuario = auth.uid() and status = 'ENVIADA' and public.eu_ativo());
create policy candidaturas_update on public.candidaturas for update to authenticated using (
  id_usuario = auth.uid()
  or exists (select 1 from public.vagas v join public.empresas e on e.id_empresa = v.id_empresa
              where v.id_vaga = candidaturas.id_vaga and e.id_usuario_responsavel = auth.uid())
);

-- ---------- NOTIFICACOES: leitura e "marcar como lida" só do próprio usuário ----------
create policy notificacoes_select on public.notificacoes for select to authenticated using (id_usuario = auth.uid());
create policy notificacoes_update on public.notificacoes for update to authenticated
  using (id_usuario = auth.uid()) with check (id_usuario = auth.uid());
revoke update on public.notificacoes from anon, authenticated;
grant update (lida) on public.notificacoes to authenticated;
