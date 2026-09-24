-- =====================================================================
-- OrientaPro · 004_seed.sql
-- Dados iniciais do teste vocacional: 5 áreas, 8 perguntas e 40 alternativas.
-- São as mesmas perguntas do site. Os nomes das áreas precisam ser
-- exatamente iguais aos do site (objeto AREAS no index), porque o site
-- liga a área do banco à área da tela pelo nome.
-- =====================================================================

insert into public.areas_profissionais (nome, descricao) values
  ('Tecnologia',                'Você gosta de resolver problemas com lógica e ferramentas digitais.'),
  ('Administração e negócios',  'Você se sente bem organizando processos, números e prazos.'),
  ('Design e criação',          'Você pensa em imagem, identidade e experiência.'),
  ('Comunicação e atendimento', 'Você tem facilidade para ouvir, explicar e convencer.'),
  ('Saúde e bem-estar',         'Você quer cuidar de pessoas e ver o resultado no dia a dia.');

-- Cada pergunta tem 5 alternativas, na ordem: Tecnologia, Administração, Design, Comunicação, Saúde.
with q(ordem, enunciado, alts) as (values
  (1, 'Num trabalho em grupo, o que você assume naturalmente?',
      array['Resolver o problema técnico','Organizar prazos e tarefas','Criar a parte visual','Apresentar para a turma','Cuidar para que todos participem bem']),
  (2, 'Qual tarefa você faria por horas sem perceber?',
      array['Montar ou consertar algo com lógica','Planejar planilhas e controlar números','Desenhar, editar ou criar layouts','Conversar e escrever para pessoas','Ajudar alguém a se sentir melhor']),
  (3, 'Como você aprende melhor?',
      array['Testando e errando no computador','Seguindo processos e checklists','Experimentando estilos e referências','Debatendo e explicando em voz alta','Praticando com pessoas e observando reações']),
  (4, 'Qual elogio combina mais com você?',
      array['Você resolve o que ninguém entende','Com você tudo fica em ordem','Você tem um olhar diferente','Você explica muito bem','Você transmite confiança e cuidado']),
  (5, 'Um cliente está insatisfeito. O que você faz?',
      array['Investigo a causa do erro','Reviso o processo e o prazo prometido','Proponho uma solução nova e criativa','Escuto com calma e negocio','Acolho e entendo como ele se sente']),
  (6, 'Qual ambiente de trabalho você prefere?',
      array['Focado, com autonomia e tela','Escritório organizado, com metas claras','Estúdio livre para criar','Movimentado, com muita gente','Atendimento próximo, pessoa a pessoa']),
  (7, 'O que mais te incomoda?',
      array['Coisas que funcionam mal sem motivo','Bagunça e falta de planejamento','Tudo igual e sem criatividade','Ficar isolado sem conversar','Ver alguém sem atenção ou cuidado']),
  (8, 'Qual projeto de faculdade você escolheria?',
      array['Um aplicativo ou sistema','Um plano de negócio','Uma campanha ou identidade visual','Um evento ou podcast','Um programa de bem-estar para a comunidade'])
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
