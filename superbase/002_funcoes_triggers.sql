-- =====================================================================
-- OrientaPro · 002_funcoes_triggers.sql
-- Funções auxiliares, triggers e as funções (RPC) chamadas pelo site.
-- =====================================================================

-- ---------- Funções auxiliares usadas nas políticas RLS ----------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios
                 where id_usuario = auth.uid() and tipo_usuario = 'ADMIN' and ativo);
$$;

create or replace function public.eu_ativo()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios where id_usuario = auth.uid() and ativo);
$$;

-- ---------- UC01: cria o perfil em USUARIOS quando o Supabase Auth cria a conta ----------
-- Os dados vêm de options.data do signUp (raw_user_meta_data).
-- O tipo ADMIN nunca pode ser escolhido pelo próprio usuário.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_tipo public.tipo_usuario_enum;
  v_nasc date;
begin
  v_tipo := case when new.raw_user_meta_data->>'tipo_usuario' = 'EMPRESA'
                 then 'EMPRESA' else 'ESTUDANTE' end;
  v_nasc := nullif(new.raw_user_meta_data->>'data_nascimento', '')::date;

  -- RN03: estudante precisa ter pelo menos 14 anos
  if v_tipo = 'ESTUDANTE' and (v_nasc is null or v_nasc > (current_date - interval '14 years')::date) then
    raise exception 'RN03: é preciso ter pelo menos 14 anos para se cadastrar.';
  end if;

  insert into public.usuarios (id_usuario, nome_completo, email, data_nascimento, tipo_usuario)
  values (new.id,
          coalesce(nullif(trim(new.raw_user_meta_data->>'nome_completo'), ''), split_part(new.email, '@', 1)),
          new.email, v_nasc, v_tipo);
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Mantém USUARIOS.email igual ao e-mail do Auth (desnormalização controlada, seção 4.5)
create or replace function public.sync_email_usuario()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.usuarios set email = new.email where id_usuario = new.id;
  return new;
end $$;

create trigger on_auth_user_email_updated
  after update of email on auth.users
  for each row when (old.email is distinct from new.email)
  execute function public.sync_email_usuario();

-- ---------- atualizado_em automático ----------
create or replace function public.set_atualizado_em()
returns trigger language plpgsql as $$
begin
  new.atualizado_em := now();
  return new;
end $$;

create trigger trg_curriculos_atualizado   before update on public.curriculos
  for each row execute function public.set_atualizado_em();
create trigger trg_candidaturas_atualizado before update on public.candidaturas
  for each row execute function public.set_atualizado_em();

-- =====================================================================
-- RPC 1 · UC05: registrar_teste
-- Recebe os ids das alternativas escolhidas, grava o teste e as respostas
-- e calcula a área recomendada (RN11) em uma única transação.
-- Roda com as permissões de quem chama (RLS continua valendo).
-- =====================================================================
create or replace function public.registrar_teste(p_alternativas bigint[])
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_uid   uuid := auth.uid();
  v_total int;
  v_resp  int;
  v_teste bigint;
  v_area  bigint;
begin
  if v_uid is null then
    raise exception 'Faça login para salvar o teste.';
  end if;

  select count(*) into v_total from public.perguntas_teste where ativa;
  select count(distinct a.id_pergunta) into v_resp
    from public.alternativas a
    join public.perguntas_teste p on p.id_pergunta = a.id_pergunta
   where a.id_alternativa = any (p_alternativas) and p.ativa;

  -- RN11: todas as perguntas ativas, uma resposta por pergunta
  if v_total = 0 or v_resp <> v_total or cardinality(p_alternativas) <> v_total then
    raise exception 'Responda todas as perguntas para concluir o teste.';
  end if;

  insert into public.testes_vocacionais (id_usuario) values (v_uid)
  returning id_teste into v_teste;

  insert into public.respostas_teste (id_teste, id_pergunta, id_alternativa)
  select v_teste, a.id_pergunta, a.id_alternativa
    from public.alternativas a
   where a.id_alternativa = any (p_alternativas);

  -- RN11: maior soma de pesos; empate → menor id_area
  select a.id_area into v_area
    from public.respostas_teste r
    join public.alternativas a on a.id_alternativa = r.id_alternativa
   where r.id_teste = v_teste
   group by a.id_area
   order by sum(a.peso) desc, a.id_area asc
   limit 1;

  update public.testes_vocacionais
     set status = 'CONCLUIDO', concluido_em = now(), id_area_recomendada = v_area
   where id_teste = v_teste;

  return jsonb_build_object(
    'id_teste', v_teste,
    'id_area',  v_area,
    'area',     (select nome from public.areas_profissionais where id_area = v_area),
    'pontos',   (select jsonb_agg(jsonb_build_object('id_area', ar.id_area, 'area', ar.nome,
                                                     'pontos', coalesce(x.pts, 0)) order by ar.id_area)
                   from public.areas_profissionais ar
                   left join (select a.id_area, sum(a.peso) as pts
                                from public.respostas_teste r
                                join public.alternativas a on a.id_alternativa = r.id_alternativa
                               where r.id_teste = v_teste
                               group by a.id_area) x on x.id_area = ar.id_area)
  );
end $$;

-- =====================================================================
-- RPC 2 · UC03: salvar_curriculo
-- Cria ou atualiza um currículo online com formações, experiências e
-- habilidades em uma única transação (ou grava tudo, ou nada).
-- p = { id_curriculo?, titulo, resumo, modelo?, origem?, telefone?, cidade?, idiomas?,
--       formacoes:[{instituicao,curso,nivel,ano_inicio,ano_fim}],
--       experiencias:[{empresa,cargo,descricao,data_inicio,data_fim}],
--       habilidades:["Excel", ...] }
-- =====================================================================
create or replace function public.salvar_curriculo(p jsonb)
returns bigint language plpgsql security invoker set search_path = '' as $$
declare
  v_uid    uuid := auth.uid();
  v_id     bigint := nullif(p->>'id_curriculo', '')::bigint;
  v_origem public.origem_curriculo_enum := coalesce(nullif(p->>'origem', ''), 'MANUAL')::public.origem_curriculo_enum;
  v_nomes  text[];
begin
  if v_uid is null then
    raise exception 'Faça login para salvar o currículo.';
  end if;
  if v_origem = 'UPLOAD' then
    raise exception 'Use o envio de PDF para currículos anexados.';
  end if;

  if v_id is null then
    insert into public.curriculos (id_usuario, titulo, resumo, modelo, origem, telefone, cidade, idiomas)
    values (v_uid, p->>'titulo', nullif(p->>'resumo', ''), coalesce(p->>'modelo', 'classico'), v_origem,
            nullif(p->>'telefone', ''), nullif(p->>'cidade', ''), nullif(p->>'idiomas', ''))
    returning id_curriculo into v_id;
  else
    update public.curriculos
       set titulo = p->>'titulo', resumo = nullif(p->>'resumo', ''), origem = v_origem,
           telefone = nullif(p->>'telefone', ''), cidade = nullif(p->>'cidade', ''),
           idiomas = nullif(p->>'idiomas', '')
     where id_curriculo = v_id and id_usuario = v_uid and origem <> 'UPLOAD';
    if not found then
      raise exception 'Currículo não encontrado.';
    end if;
    delete from public.formacoes             where id_curriculo = v_id;
    delete from public.experiencias          where id_curriculo = v_id;
    delete from public.curriculo_habilidades where id_curriculo = v_id;
  end if;

  insert into public.formacoes (id_curriculo, instituicao, curso, nivel, ano_inicio, ano_fim)
  select v_id, x.instituicao, x.curso, x.nivel::public.nivel_formacao_enum, x.ano_inicio, x.ano_fim
    from jsonb_to_recordset(coalesce(p->'formacoes', '[]'::jsonb))
         as x(instituicao text, curso text, nivel text, ano_inicio int, ano_fim int);

  insert into public.experiencias (id_curriculo, empresa, cargo, descricao, data_inicio, data_fim)
  select v_id, x.empresa, x.cargo, nullif(x.descricao, ''), x.data_inicio, x.data_fim
    from jsonb_to_recordset(coalesce(p->'experiencias', '[]'::jsonb))
         as x(empresa text, cargo text, descricao text, data_inicio date, data_fim date);

  select coalesce(array_agg(distinct left(trim(h), 60)), '{}') into v_nomes
    from jsonb_array_elements_text(coalesce(p->'habilidades', '[]'::jsonb)) h
   where trim(h) <> '';

  insert into public.habilidades (nome)
  select unnest(v_nomes)
  on conflict (nome) do nothing;

  insert into public.curriculo_habilidades (id_curriculo, id_habilidade)
  select v_id, h.id_habilidade from public.habilidades h where h.nome = any (v_nomes);

  return v_id;
end $$;

-- Permissões de execução das RPCs (apenas usuários autenticados)
revoke execute on function public.registrar_teste(bigint[]) from public, anon;
revoke execute on function public.salvar_curriculo(jsonb)   from public, anon;
grant  execute on function public.registrar_teste(bigint[]) to authenticated;
grant  execute on function public.salvar_curriculo(jsonb)   to authenticated;
