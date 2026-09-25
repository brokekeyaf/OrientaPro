-- =====================================================================
-- OrientaPro · 006_teste_dinamico_desafios.sql
-- Rode UMA vez no SQL Editor, depois dos arquivos 001 a 005.
--  1. Amplia o banco de perguntas do teste vocacional de 8 para 20.
--  2. Ajusta registrar_teste: o site sorteia 8 perguntas (mais até 2 de
--     desempate), então não exige mais responder TODAS as perguntas do banco.
--  3. Cria a tabela DESAFIOS_AREA (desafio prático de 1 hora por área).
-- =====================================================================

-- ---------- 1. Mais 12 perguntas (alternativas na ordem: Tecnologia, Administração, Design, Comunicação, Saúde) ----------
with q(ordem, enunciado, alts) as (values
  (9,  'Numa festa ou evento, onde você se imagina?',
       array['Cuidando do som, das luzes e dos equipamentos','Controlando a lista, o orçamento e os horários','Decorando e pensando no visual','Recebendo e conversando com os convidados','Garantindo que todo mundo esteja bem e confortável']),
  (10, 'Que tipo de vídeo você mais assiste?',
       array['Tecnologia, games ou lançamentos de aparelhos','Finanças, empreendedorismo ou negócios','Arte, design, moda ou edição','Entrevistas, podcasts ou debates','Saúde, beleza, treino ou autocuidado']),
  (11, 'Um amigo pede ajuda. Qual pedido você resolve mais rápido?',
       array['Consertar o celular ou o computador','Organizar as contas do mês','Criar a arte do perfil ou do negócio dele','Escrever uma mensagem difícil ou ensaiar uma conversa','Indicar um cuidado para a pele, o corpo ou o bem-estar']),
  (12, 'Na escola, em qual atividade você se saía melhor?',
       array['Exercícios de lógica e cálculo','Planejar o trabalho em grupo e dividir as tarefas','Cartazes, maquetes e apresentações visuais','Seminários e debates','Aulas sobre o corpo humano, biologia ou educação física']),
  (13, 'Se ganhasse um dia livre para aprender algo, você escolheria…',
       array['Programar um joguinho','Montar um pequeno negócio online','Editar fotos e vídeos','Um curso de oratória','Um curso de primeiros socorros ou de massagem']),
  (14, 'Qual frase mais parece com você?',
       array['Gosto de entender como as coisas funcionam por dentro','Gosto de listas, metas e tudo no lugar','Gosto de deixar tudo mais bonito','Gosto de conversar e conhecer gente nova','Gosto de ajudar as pessoas a se sentirem bem']),
  (15, 'Numa loja, que função você escolheria?',
       array['Cuidar do sistema e do site','Cuidar do estoque e do caixa','Montar a vitrine e as redes sociais','Atender e vender para os clientes','Orientar clientes sobre produtos de cuidado pessoal']),
  (16, 'O que te deixa orgulhoso(a) no fim do dia?',
       array['Ter resolvido um problema difícil','Ter terminado tudo o que estava planejado','Ver pronto algo que eu criei','Ter convencido ou ajudado alguém numa boa conversa','Ver alguém melhor por causa do meu cuidado']),
  (17, 'Como você prefere trabalhar?',
       array['Concentrado(a), com fone e sem interrupções','Com rotina e processos claros','Com liberdade para experimentar','Em equipe, falando com muita gente','Perto das pessoas, atendendo uma de cada vez']),
  (18, 'Qual ferramenta você gostaria de dominar?',
       array['Uma linguagem de programação','Planilhas e sistemas de gestão','Canva, Photoshop ou um editor de vídeo','Microfone e câmera, para apresentar e gravar','Equipamentos e técnicas de estética ou saúde']),
  (19, 'Quando algo dá errado num grupo, você…',
       array['Procura a causa técnica do problema','Refaz o plano e redistribui as tarefas','Sugere um jeito diferente de fazer','Conversa com todos para acalmar e alinhar','Cuida de quem ficou mais abalado']),
  (20, 'Qual notícia chamaria mais a sua atenção?',
       array['Nova inteligência artificial é lançada','Empresa de jovens fatura milhões','Campanha criativa viraliza nas redes','Entrevista com um grande comunicador','Nova técnica de cuidado com a saúde e a pele'])
),
ins as (
  insert into public.perguntas_teste (ordem, enunciado)
  select ordem, enunciado from q
  returning id_pergunta, ordem
),
areas as (
  select id_area, row_number() over (order by id_area) as pos from public.areas_profissionais
)
insert into public.alternativas (id_pergunta, id_area, texto, peso)
select ins.id_pergunta, areas.id_area, q.alts[areas.pos], 1
  from q
  join ins   on ins.ordem = q.ordem
  join areas on areas.pos between 1 and 5
 order by q.ordem, areas.pos;

-- ---------- 2. registrar_teste para teste sorteado ----------
-- RN11 (revisada): mínimo de 8 perguntas ativas diferentes, uma alternativa por pergunta.
create or replace function public.registrar_teste(p_alternativas bigint[])
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_uid   uuid := auth.uid();
  v_alts  int;
  v_perg  int;
  v_teste bigint;
  v_area  bigint;
  v_min   constant int := 8;
begin
  if v_uid is null then
    raise exception 'Faça login para salvar o teste.';
  end if;

  select count(*), count(distinct a.id_pergunta) into v_alts, v_perg
    from public.alternativas a
    join public.perguntas_teste p on p.id_pergunta = a.id_pergunta
   where a.id_alternativa = any (p_alternativas) and p.ativa;

  -- todas as alternativas existem, sem repetição, uma por pergunta, e pelo menos 8 perguntas
  if v_alts <> cardinality(p_alternativas) or v_perg <> v_alts or v_perg < v_min then
    raise exception 'Responda todas as perguntas sorteadas para concluir o teste.';
  end if;

  insert into public.testes_vocacionais (id_usuario) values (v_uid)
  returning id_teste into v_teste;

  insert into public.respostas_teste (id_teste, id_pergunta, id_alternativa)
  select v_teste, a.id_pergunta, a.id_alternativa
    from public.alternativas a
   where a.id_alternativa = any (p_alternativas);

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

revoke execute on function public.registrar_teste(bigint[]) from public, anon;
grant  execute on function public.registrar_teste(bigint[]) to authenticated;

-- ---------- 3. Tabela 17: DESAFIOS_AREA (RF19) ----------
create table public.desafios_area (
  id_desafio        bigint generated always as identity primary key,
  id_usuario        uuid not null references public.usuarios(id_usuario) on delete cascade,
  id_area           bigint not null references public.areas_profissionais(id_area) on delete restrict,
  nota              smallint not null check (nota between 1 and 5),        -- "Gostou dessa área?"
  anotacao          varchar(1000),
  passos_concluidos smallint not null default 0 check (passos_concluidos >= 0),
  concluido_em      timestamptz not null default now(),
  constraint uq_desafios_usuario_area unique (id_usuario, id_area)         -- uma avaliação por área (refazer atualiza)
);
create index on public.desafios_area (id_usuario);

alter table public.desafios_area enable row level security;
create policy desafios_select on public.desafios_area for select to authenticated using (id_usuario = auth.uid());
create policy desafios_insert on public.desafios_area for insert to authenticated
  with check (id_usuario = auth.uid() and public.eu_ativo());
create policy desafios_update on public.desafios_area for update to authenticated
  using (id_usuario = auth.uid()) with check (id_usuario = auth.uid());
create policy desafios_delete on public.desafios_area for delete to authenticated using (id_usuario = auth.uid());
